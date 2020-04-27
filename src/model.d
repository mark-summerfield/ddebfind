// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

struct Model {
    import qtrac.debfind.common: StringSet;
    import qtrac.debfind.deb: Deb;
    import qtrac.debfind.modelutil: DebNames, NameAndDescription;
    import qtrac.debfind.query: Query;
    import std.stdio: File;

    private {
        enum PACKAGE_DIR = "/var/lib/apt/lists";
        enum PACKAGE_PATTERN = "*Packages";

        Deb[string] debForName;
        DebNames[string] namesForStemmedDescription;
        DebNames[string] namesForStemmedName;
        DebNames[string] namesForSection;
        StringSet allSections;
        StringSet allNames;
    }

    size_t length() const { return debForName.length; }

    const(StringSet) sections() const { return allSections; }

    const(StringSet) names() const { return allNames; }

    DebNames query(const Query query) const {
        import qtrac.debfind.modelutil: stemmedWords;
        import std.array: array;
        import std.range: empty;
        import std.string: startsWith;

        DebNames haveSection;
        DebNames haveDescription;
        DebNames haveName;
        bool constrainToSection;
        bool constrainToDescription;
        bool constrainToName;

        if (!query.section.empty) {
            constrainToSection = true;
            if (auto names = query.section in namesForSection)
                haveSection = names.dup;
        }
        if (!query.descriptionWords.empty) {
            constrainToDescription = true;
            auto words = stemmedWords(query.descriptionWords).array;
            foreach (word; words) { 
                if (auto names = word in namesForStemmedDescription)
                    haveDescription |= *names;
            }
            // haveDescription is names matching Any word
            // Only accept matching All (doesn't apply if only one word)
            if (words.length > 1 && !query.matchAnyDescriptionWord)
                foreach (word; words) { 
                    if (auto names = word in namesForStemmedDescription)
                        haveDescription &= *names;
                }
        }
        if (!query.nameWords.empty) {
            constrainToName = true;
            auto words = stemmedWords(query.nameWords).array;
            foreach (word; words) { 
                if (auto names = word in namesForStemmedDescription)
                    haveName |= *names;
            }
            // haveName is names matching Any word
            // Only accept matching All (doesn't apply if only one word)
            if (words.length > 1 && !query.matchAnyNameWord)
                foreach (word; words) { 
                    if (auto names = word in namesForStemmedDescription)
                        haveName &= *names;
                }
        }
        DebNames names = allNames.dup;
        if (constrainToSection)
            names &= haveSection;
        if (constrainToDescription)
            names &= haveDescription;
        if (constrainToName)
            names &= haveName;
        if (query.includeLibraries)
            return names;
        DebNames result; // filter out libraries
        foreach (name; names)
            if (name.startsWith("libre") || !name.startsWith("lib"))
                result.add(name);
        return result;
    }

    NameAndDescription[] namesAndDescriptions(DebNames names) {
        import std.algorithm: sort;

        NameAndDescription[] namesAndDescriptions;
        foreach (name; names)
            namesAndDescriptions ~= NameAndDescription(
                name, debForName[name].description);
        namesAndDescriptions.sort;
        return namesAndDescriptions;
    }

    void readPackages(void delegate(bool, size_t) onReady) {
        if (!loadFromCache(onReady))
            readAndIndexPackages(onReady);
    }

    void refresh(void delegate(bool, size_t) onReady) {
        deleteCache;
        readPackages(onReady);
    }

    private void readAndIndexPackages(void delegate(bool, size_t) onReady) {
        import qtrac.debfind.modelutil: readPackageFile;
        import std.algorithm: max;
        import std.array: array;
        import std.parallelism: taskPool, totalCPUs;
        import std.file: dirEntries, FileException, SpanMode;

        try {
            auto filenames = dirEntries(PACKAGE_DIR, PACKAGE_PATTERN,
                                        SpanMode.shallow).array;
            auto units = max(2, (totalCPUs / 2) - 2);
            foreach (debs; taskPool.map!readPackageFile(filenames, units))
                foreach (deb; debs)
                    debForName[deb.name] = deb.dup;
            onReady(false, filenames.length);
            makeIndexes;
            saveToCache;
            onReady(true, filenames.length);
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read packages: ", err);
        }
    }

    private void makeIndexes() {
        import qtrac.debfind.modelutil: makeNamesForStemmedDescription,
               makeNamesForStemmedName, makeNamesForSection;
        import std.array: array;
        import std.parallelism: task;

        const debs = debForName.byValue.array;
        // Start from (best guess) slowest to fastest
        auto stemmedDescriptionsTask = task!makeNamesForStemmedDescription(
            debs);
        stemmedDescriptionsTask.executeInNewThread;
        auto stemmedNamesTask = task!makeNamesForStemmedName(debs);
        stemmedNamesTask.executeInNewThread;
        auto sectionsTask = task!makeNamesForSection(debs);
        sectionsTask.executeInNewThread;
        // End from (best guess) fastest to slowest
        auto sectionsTuple = sectionsTask.yieldForce;
        allSections = sectionsTuple.set;
        namesForSection = sectionsTuple.namesFor;
        auto namesTuple = stemmedNamesTask.yieldForce;
        allNames = namesTuple.set;
        namesForStemmedName = namesTuple.namesFor;
        namesForStemmedDescription = stemmedDescriptionsTask.yieldForce;
    }

    private bool loadFromCache(void delegate(bool, size_t) onReady) {
        import qtrac.debfind.modelutil: cacheFilename, getNextCachedState,
               PREFIX, readCachedDeb, readCachedIndex, readCachedSection,
               State, SUFFIX;
        import std.exception: ErrnoException;
        import std.file: exists;
        import std.stdio: stderr;
        import std.string: chomp, endsWith, startsWith;

        string filename = cacheFilename(); 
        if (!filename.exists)
            return false;
        auto state = State.Unknown;
        debForName.clear;
        namesForStemmedDescription.clear;
        namesForStemmedName.clear;
        namesForSection.clear;
        allSections.clear;
        allNames.clear;
        int lino = 1;
        string line;
        auto file = File(filename, "r");
        try {
            while ((line = file.readln()) !is null) {
                line = line.chomp;
                if (line.startsWith(PREFIX) && line.endsWith(SUFFIX))
                    state = getNextCachedState(line);
                else final switch (state) {
                    case State.Debs:
                        readCachedDeb(line, debForName, allNames);
                        break;
                    case State.Descriptions:
                        readCachedIndex(line, namesForStemmedDescription);
                        break;
                    case State.Names:
                        readCachedIndex(line, namesForStemmedName);
                        break;
                    case State.Sections:
                        readCachedSection(line, namesForSection,
                                          allSections);
                        break;
                    case State.Unknown:
                        stderr.writeln(lino, ": Unknown: ", line);
                        break;
                }
                lino++;
            }
            onReady(true, 0); // 0 => read from cache
            return true;
        } catch (ErrnoException err) {
            import std.stdio: stderr;
            stderr.writeln(lino, ": failed to read cache: ", err);
            return false;
        }
    }

    // We never delete the cache (leave that to the OS since it is in
    // /tmp), unless we fail to create it or the user calls refresh().
    private void saveToCache() {
        import qtrac.debfind.modelutil: cacheFilename, DEB_FOR_NAME,
               INDENT, ITEM_SEP, NAMES_FOR_SECTION,
               NAMES_FOR_STEMMED_DESCRIPTION, NAMES_FOR_STEMMED_NAME, NL,
               TAB;
        import std.array: array;
        import std.exception: ErrnoException;
        import std.string: join, replace;

        auto file = File(cacheFilename(), "w");
        try {
            file.writeln(DEB_FOR_NAME);
            foreach (deb; debForName)
                file.writeln(
                    deb.name, TAB, deb.ver, TAB, deb.section, TAB,
                    deb.url, TAB, deb.size, TAB,
                    deb.description.replace(NL, ITEM_SEP)
                                   .replace(TAB, INDENT));
            file.writeln(NAMES_FOR_STEMMED_DESCRIPTION);
            foreach (word, names; namesForStemmedDescription)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_STEMMED_NAME);
            foreach (word, names; namesForStemmedName)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_SECTION);
            foreach (word, names; namesForSection)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
        } catch (ErrnoException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to write cache: ", err);
            deleteCache;
        }
    }

    private void deleteCache() {
        import qtrac.debfind.modelutil: cacheFilename;
        import std.file: FileException, remove;

        try {
            remove(cacheFilename());
        } catch (FileException) {
            // Doesn't matter if it doesn't exist
        }
    }

    version(unittest) {
        void dumpCsv(string filename) {
            import qtrac.debfind.modelutil: stemmedWords;
            import std.array: array, join;
            import std.stdio: File, stderr, writeln, writefln;
            import std.algorithm: sort;
            stderr.writefln("dumpCsv(\"%s\")", filename);
            auto file = File(filename, "w");
            file.writeln("Name,Section,NameStems,DescStems");
            foreach (deb; debForName) {
                file.writefln("%s,%s,%s,\"%s\",\"%s\",\"%s\"",
                              deb.name, deb.section,
                              join(stemmedWords(deb.name), ","),
                              join(stemmedWords(deb.description)));
            }
        }
        void dumpDebs() {
            import std.stdio: stderr, writeln;
            stderr.writeln("dumpDebs");
            foreach (deb; debForName)
                writeln(deb);
        }
        void dumpStemmedNameIndex() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpStemmedNameIndex");
            writeln("StemmedName: Deb names");
            foreach (word, names; namesForStemmedName) {
                write(word, ":");
                foreach (name; sort(names.array))
                    write(" ", name);
                writeln;
            }
        }
        void dumpStemmedDescriptionIndex() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpStemmedDescriptionIndex");
            writeln("StemmedWord: Deb names");
            foreach (word, names; namesForStemmedDescription) {
                write(word, ":");
                foreach (name; sort(names.array))
                    write(" ", name);
                writeln;
            }
        }
        void dumpSectionIndex() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpSectionIndex");
            writeln("section: Deb names");
            foreach (section, names; namesForSection) {
                write(section, ":");
                foreach (name; sort(names.array))
                    write(" ", name);
                writeln;
            }
        }
        void dumpAlls() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, writeln;
            stderr.writeln("dumpAlls");
            writeln("@@allSections@@");
            foreach (section; sort(allSections.array))
                writeln(section);
            writeln("@@allNames@@");
            foreach (name; sort(allNames.array))
                writeln(name);
        }
    }
}

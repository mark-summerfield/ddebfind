// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

import qtrac.debfind.deb: Deb;
import qtrac.debfind.kind: Kind;
import qtrac.debfind.modelutil: DebNames;
import std.stdio: File;

struct Model {
    import qtrac.debfind.common: StringSet;
    import qtrac.debfind.query: Query;

    private {
        enum PACKAGE_DIR = "/var/lib/apt/lists";
        enum PACKAGE_PATTERN = "*Packages";

        Deb[string] debForName;
        DebNames[string] namesForStemmedDescription;
        DebNames[string] namesForStemmedName;
        DebNames[Kind] namesForKind;
        DebNames[string] namesForSection;
        DebNames[string] namesForTag;
        StringSet allTags;
        StringSet allSections;
        StringSet allNames;
    }

    size_t length() const { return debForName.length; }

    const(StringSet) tags() const { return allTags; }

    const(StringSet) sections() const { return allSections; }

    const(StringSet) names() const { return allNames; }

    DebNames query(const Query query) const {
        import qtrac.debfind.modelutil: stemmedWords;
        import std.array: array;
        import std.range: empty;

        DebNames haveTag;
        DebNames haveKind;
        DebNames haveSection;
        DebNames haveDescription;
        DebNames haveName;
        bool constrainToTag;
        bool constrainToKind;
        bool constrainToSection;
        bool constrainToDescription;
        bool constrainToName;

        if (!query.tag.empty) {
            constrainToTag = true;
            if (auto names = query.tag in namesForTag)
                haveTag = names.dup;
        }
        if (query.kind !is Kind.Any) {
            constrainToKind = true;
            if (auto names = query.kind in namesForKind)
                haveKind = names.dup;
        }
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
        DebNames result = allNames.dup;
        if (constrainToTag)
            result &= haveTag;
        if (constrainToKind)
            result &= haveKind;
        if (constrainToSection)
            result &= haveSection;
        if (constrainToDescription)
            result &= haveDescription;
        if (constrainToName)
            result &= haveName;
        return result;
    }

    void readPackages(void delegate(bool, size_t) onReady) {
        if (!loadFromCache(onReady))
            readAndIndexPackages(onReady);
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
               makeNamesForStemmedName, makeNamesForTag, makeNamesForKind,
               makeNamesForSection;
        import std.array: array;
        import std.parallelism: task;

        const debs = debForName.byValue.array;
        // Start from (best guess) slowest to fastest
        auto stemmedDescriptionsTask = task!makeNamesForStemmedDescription(
            debs);
        stemmedDescriptionsTask.executeInNewThread;
        auto stemmedNamesTask = task!makeNamesForStemmedName(debs);
        stemmedNamesTask.executeInNewThread;
        auto tagsTask = task!makeNamesForTag(debs);
        tagsTask.executeInNewThread;
        auto kindsTask = task!makeNamesForKind(debs);
        kindsTask.executeInNewThread;
        auto sectionsTask = task!makeNamesForSection(debs);
        sectionsTask.executeInNewThread;
        // End from (best guess) fastest to slowest
        auto sectionsTuple = sectionsTask.yieldForce;
        allSections = sectionsTuple.set;
        namesForSection = sectionsTuple.namesFor;
        auto kindTuple = kindsTask.yieldForce;
        allNames = kindTuple.set;
        namesForKind = kindTuple.namesFor;
        auto tagsTuple = tagsTask.yieldForce;
        allTags = tagsTuple.set;
        namesForTag = tagsTuple.namesFor;
        namesForStemmedName = stemmedNamesTask.yieldForce;
        namesForStemmedDescription = stemmedDescriptionsTask.yieldForce;
    }

    bool loadFromCache(void delegate(bool, size_t) onReady) {
        import qtrac.debfind.modelutil: cacheFilename, getNextCachedState,
               PREFIX, readCachedDeb, readCachedKind, readCachedIndex,
               readCachedSection, readCachedTags, State, SUFFIX;
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
        namesForKind.clear;
        namesForSection.clear;
        namesForTag.clear;
        allTags.clear;
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
                    case State.Kinds:
                        readCachedKind(line, namesForKind);
                        break;
                    case State.Sections:
                        readCachedSection(line, namesForSection,
                                          allSections);
                        break;
                    case State.Tags:
                        readCachedTags(line, namesForTag, allTags);
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
    // /tmp), unless we fail to create it.
    void saveToCache() {
        import qtrac.debfind.kind: toString;
        import qtrac.debfind.modelutil: cacheFilename, DEB_FOR_NAME,
               INDENT, ITEM_SEP, NAMES_FOR_KIND, NAMES_FOR_SECTION,
               NAMES_FOR_STEMMED_DESCRIPTION, NAMES_FOR_STEMMED_NAME,
               NAMES_FOR_TAG, NL, TAB;
        import std.array: array;
        import std.exception: ErrnoException;
        import std.string: join, replace;

        auto file = File(cacheFilename(), "w");
        try {
            file.writeln(DEB_FOR_NAME);
            foreach (deb; debForName)
                file.writeln(
                    deb.name, TAB, deb.ver, TAB, deb.section, TAB,
                    deb.url, TAB, deb.size, TAB, deb.kind.toString, TAB,
                    join(deb.tags.array, ITEM_SEP), TAB,
                    deb.description.replace(NL, ITEM_SEP)
                                   .replace(TAB, INDENT));
            file.writeln(NAMES_FOR_STEMMED_DESCRIPTION);
            foreach (word, names; namesForStemmedDescription)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_STEMMED_NAME);
            foreach (word, names; namesForStemmedName)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_KIND);
            foreach (kind, names; namesForKind)
                file.writeln(kind.toString, TAB,
                             join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_SECTION);
            foreach (word, names; namesForSection)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_TAG);
            foreach (word, names; namesForTag)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
        } catch (ErrnoException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to write cache: ", err);
            deleteCache;
        }
    }

    void deleteCache() {
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
            file.writeln("Name,Section,Kind,NameStems,DescStems,Tags");
            foreach (deb; debForName) {
                file.writefln("%s,%s,%s,\"%s\",\"%s\",\"%s\"",
                              deb.name, deb.section, deb.kind,
                              join(stemmedWords(deb.name), ","),
                              join(stemmedWords(deb.description), ","),
                              join(sort(deb.tags.array), ","));
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
        void dumpKindIndex() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpKindIndex");
            writeln("Kind: Deb names");
            foreach (kind, names; namesForKind) {
                write(kind, ":");
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
        void dumpTagIndex() {
            import std.algorithm: sort;
            import std.array: array;
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpTagIndex");
            writeln("tag: Deb names");
            foreach (tag, names; namesForTag) {
                write(tag, ":");
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
            writeln("@@allTags@@");
            foreach (tag; sort(allTags.array))
                writeln(tag);
            writeln("@@allSections@@");
            foreach (section; sort(allSections.array))
                writeln(section);
            writeln("@@allNames@@");
            foreach (name; sort(allNames.array))
                writeln(name);
        }
    }
}

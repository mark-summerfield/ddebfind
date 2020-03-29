// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

import qtrac.debfind.deb: Deb, Kind;
import std.stdio: File;

private {
    import qtrac.debfind.common: StringSet;
    import std.typecons: Tuple;

    alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                 bool, "ok");
    alias DebNames = StringSet;
    alias SetAndAA = Tuple!(StringSet, "set", DebNames[string], "namesFor");
    alias SetAndKindAA = Tuple!(StringSet, "set", DebNames[Kind],
                                "namesFor");
    enum TAB = '\t';
    enum ITEM_SEP = '\v';
    enum INDENT = "    ";
    enum DEB_FOR_NAME = "INDEX debForName";
    enum NAMES_FOR_STEMMED_DESCRIPTION =
        "INDEX namesForStemmedDescription";
    enum NAMES_FOR_STEMMED_NAME = "INDEX namesForStemmedName";
    enum NAMES_FOR_KIND = "INDEX namesForKind";
    enum NAMES_FOR_SECTION = "INDEX namesForSection";
    enum NAMES_FOR_TAG = "INDEX namesForTag";
    enum State { Unknown, Debs, Descriptions, Names, Kinds, Sections, Tags }
}

struct Model {
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
        import std.exception: ErrnoException;
        import std.file: exists;
        import std.string: chomp;

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
        string line;
        auto file = File(filename, "r");
        try {
            while ((line = file.readln()) !is null) {
                line = line.chomp;
                final switch (state) {
                    case State.Unknown: state = getState(line); break;
                    // TODO
                    case State.Debs: break;
                    case State.Descriptions: break;
                    case State.Names: break;
                    case State.Kinds: break;
                    case State.Sections: break;
                    case State.Tags: break;
                }
            }
            // populate all* as we read
// TODO uncomment once it works
//            onReady(true, 0); // 0 => read from cache
//            return true;
        } catch (ErrnoException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read cache: ", err);
            return false;
        }
        return false;
    }

    void saveToCache() {
        import std.array: array;
        import std.exception: ErrnoException;
        import std.string: join, replace;

        auto file = File(cacheFilename(), "w");
        try {
            file.writeln(DEB_FOR_NAME);
            foreach (deb; debForName)
                file.writeln(
                    deb.name, TAB, deb.ver, TAB, deb.section, TAB,
                    deb.url, TAB, deb.size, TAB, cast(int)deb.kind, TAB,
                    join(deb.tags.array, ITEM_SEP), TAB,
                    deb.description.replace('\n', ITEM_SEP)
                                   .replace(TAB, INDENT));
            file.writeln(NAMES_FOR_STEMMED_DESCRIPTION);
            foreach (word, names; namesForStemmedDescription)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_STEMMED_NAME);
            foreach (word, names; namesForStemmedName)
                file.writeln(word, TAB, join(names.array, ITEM_SEP));
            file.writeln(NAMES_FOR_KIND);
            foreach (kind, names; namesForKind)
                file.writeln(cast(int)kind, TAB,
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

    void close() { deleteCache; }

    void deleteCache() {
        import std.file: FileException, remove;

        try {
// TODO uncomment
//            remove(cacheFilename());
        } catch (FileException) {
            // Doesn't matter if it doesn't exist
        }
    }

    version(unittest) {
        void dumpCsv(string filename) {
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
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpStemmedNameIndex");
            import std.range: empty;
            writeln("StemmedName: Deb names");
            foreach (word, names; namesForStemmedName) {
                write(word, ":");
                foreach (name; names)
                    write(" ", name);
                writeln;
            }
        }
        void dumpStemmedDescriptionIndex() {
            import std.stdio: stderr, write, writeln;
            stderr.writeln("dumpStemmedDescriptionIndex");
            import std.range: empty;
            writeln("StemmedWord: Deb names");
            foreach (word, names; namesForStemmedDescription) {
                write(word, ":");
                foreach (name; names)
                    write(" ", name);
                writeln;
            }
        }
    }
}

private Deb[] readPackageFile(string filename) {
    import std.file: FileException;
    import std.range: enumerate;
    import std.stdio: File, stderr;

    Deb[] debs;
    Deb deb;
    try {
        bool inDescription = false; // Descriptions can by multi-line
        bool inContinuation = false; // Other things can be multi-line
        auto file = File(filename);
        foreach(lino, line; file.byLine.enumerate(1))
            readPackageLine(debs, deb, line, inDescription, inContinuation);
        if (deb.valid)
            debs ~= deb.dup;
    } catch (FileException err) {
        stderr.writefln("error: %s: failed to read packages: %s",
                        filename, err);
    }
    return debs;
}

private void readPackageLine(ref Deb[] debs, ref Deb deb,
                             const(char[]) line, ref bool inDescription,
                             ref bool inContinuation) {
    import std.conv: to;
    import std.stdio: stderr;
    import std.string: empty, startsWith, strip;

    if (strip(line).empty) {
        if (deb.valid) {
            debs ~= deb.dup;
            deb.clear;
        }
        return;
    }
    if (inDescription || inContinuation) {
        if (line.startsWith(' ') || line.startsWith('\t')) {
            if (inDescription)
                deb.description ~= line;
            return;
        }
        inDescription = inContinuation = false;
    }
    immutable keyValue = maybeKeyValue(line);
    if (!keyValue.ok) 
        inContinuation = true;
    else
        inDescription = populateDeb(deb, keyValue.key, keyValue.value);
}

private MaybeKeyValue maybeKeyValue(const(char[]) line) {
    import std.string: indexOf, strip;

    immutable i = line.indexOf(':');
    if (i == -1)
        return MaybeKeyValue("", "", false);
    immutable key = strip(line[0..i]).idup;
    immutable value = strip(line[i + 1..$]).idup;
    return MaybeKeyValue(key, value, true);
}

private bool populateDeb(ref Deb deb, const string key,
                         const string value) {
    import std.conv: to;

    switch (key) {
        case "Package":
            deb.name = value;
            maybeSetKindForName(deb);
            return false;
        case "Version":
            deb.ver = value;
            return false;
        case "Section":
            deb.section = value;
            maybeSetKindForSection(deb);
            return false;
        case "Description", "Npp-Description": // XXX ignore Npp-?
            deb.description ~= value;
            return true; // We are now in a description
        case "Homepage":
            deb.url = value;
            return false;
        case "Installed-Size":
            deb.size = value.to!size_t;
            return false;
        case "Tag":
            maybePopulateTags(deb, value);
            return false;
        case "Depends":
            maybeSetKindForDepends(deb, value);
            return false;
        default: return false; // Ignore "uninteresting" fields
    }
}

private void maybeSetKindForName(ref Deb deb) {
    import std.string: startsWith;

    if (deb.kind is Kind.Unknown) {
        if (deb.name.startsWith("libreoffice"))
            deb.kind = Kind.GuiApp;
        else if (deb.name.startsWith("lib"))
            deb.kind = Kind.Library;
    }
}

private void maybeSetKindForSection(ref Deb deb) {
    import std.algorithm: canFind;
    import std.string: startsWith;

    if (deb.kind is Kind.Unknown) {
        if (canFind(deb.section, "Desktop") ||
                canFind(deb.section, "Graphical"))
            deb.kind = Kind.GuiApp;
        else if (deb.section.startsWith("Documentation"))
            deb.kind = Kind.Documentation;
        else if (deb.section.startsWith("Fonts"))
            deb.kind = Kind.Font;
        else if (deb.section.startsWith("Libraries"))
            deb.kind = Kind.Library;
    }
}

private void maybePopulateTags(ref Deb deb, const string tags) {
    import std.regex: ctRegex, split;

    auto rx = ctRegex!(`\s*,\s*`);
    foreach (tag; tags.split(rx)) {
        deb.tags.add(tag);
        maybeSetKindForTag(deb, tag);
    }
}

private void maybeSetKindForTag(ref Deb deb, const string tag) {
    import std.string: startsWith;

    if (deb.kind is Kind.Unknown) {
        if (tag.startsWith("office::") || tag.startsWith("uitoolkit::") ||
                tag.startsWith("x11::")) {
            deb.kind = Kind.GuiApp;
        }
        else switch (tag) {
            case "interface::cli", "interface::shell",
                 "interface::text-mode", "interface::svga":
                deb.kind = Kind.ConsoleApp;
                break;
            case "interface::graphical", "interface::x11",
                 "junior::games-gl", "suite::gimp", "suite::gnome",
                 "suite::kde", "suite::netscape", "suite::openoffice",
                 "suite::xfce":
                deb.kind = Kind.GuiApp;
                break;
            case "role::data":
                deb.kind = Kind.Data;
                break;
            case "role::devel-lib", "role::plugin", "role::shared-lib":
                deb.kind = Kind.Library;
                break;
            case "role::documentation":
                deb.kind = Kind.Documentation;
                break;
            default: break;
        }
    }
}

private void maybeSetKindForDepends(ref Deb deb, const string depends) {
    import std.regex: ctRegex, matchFirst;

    auto rx = ctRegex!(`\blib(gtk|qt|tk|x11|fltk|motif|sdl|wx)|gnustep`);
    if (deb.kind is Kind.Unknown && matchFirst(depends, rx))
        deb.kind = Kind.GuiApp;
}

private auto stemmedWords(const string line) {
    import std.algorithm: filter, map;
    import std.array: array;
    import std.conv: to;
    import std.regex: ctRegex, replaceAll;
    import std.string: isNumeric, split;
    import std.uni: toLower;
    import stemmer: Stemmer;

    auto nonLetterRx = ctRegex!(`\W+`);
    Stemmer stemmer;
    return filter!(word => !word.isNumeric && word.length > 1)
                  (map!(word => stemmer.stem(word).to!string)
                       (replaceAll(line, nonLetterRx, " ").toLower.split));
}

private void updateIndex(ref DebNames[string] index, const string word,
                         const string name) {
    if (auto debnames = word in index)
        debnames.add(name);
    else
        index[word] = DebNames(name);
}

private void addIndexAlias(ref DebNames[string] index, string original,
                           string aliased) {
    if (auto debnames = original in index) {
        if (auto aliasedNames = aliased in index)
            *aliasedNames |= *debnames;
        else
            index[aliased] = *debnames;
    }
}

// The words of the deb's name are considered to be part of the description
private auto makeNamesForStemmedDescription(ref const Deb[] debs) {
    import qtrac.debfind.common: COMMON_STEMS;
    import std.algorithm: filter;
    import std.range: chain;
    import std.string: empty, startsWith;

    DebNames[string] namesForStemmedDescription;
    foreach (deb; debs) {
        foreach (word; chain(stemmedWords(deb.description),
                             filter!(w => !w.startsWith("lib"))
                                    (stemmedWords(deb.name))))
            if (!word.empty && word !in COMMON_STEMS)
                updateIndex(namesForStemmedDescription, word, deb.name);
    }
    addIndexAlias(namesForStemmedDescription, "python3", "python");
    return namesForStemmedDescription;
}

private auto makeNamesForStemmedName(ref const Deb[] debs) {
    import qtrac.debfind.common: COMMON_STEMS;
    import std.string: empty;

    DebNames[string] namesForStemmedName;
    foreach (deb; debs) {
        foreach (word; stemmedWords(deb.name))
            if (!word.empty && word !in COMMON_STEMS)
                updateIndex(namesForStemmedName, word, deb.name);
    }
    return namesForStemmedName;
}

private auto makeNamesForKind(ref const Deb[] debs) {
    DebNames[Kind] namesForKind;
    StringSet allNames;
    foreach (deb; debs) {
        allNames.add(deb.name);
        if (auto debnames = deb.kind in namesForKind)
            debnames.add(deb.name);
        else
            namesForKind[deb.kind] = DebNames(deb.name);
    }
    return SetAndKindAA(allNames, namesForKind);
}

private SetAndAA makeNamesForSection(ref const Deb[] debs) {
    DebNames[string] namesForSection;
    StringSet allSections;
    foreach (deb; debs) {
        allSections.add(deb.section);
        if (auto debnames = deb.section in namesForSection)
            debnames.add(deb.name);
        else
            namesForSection[deb.section] = DebNames(deb.name);
    }
    return SetAndAA(allSections, namesForSection);
}

private SetAndAA makeNamesForTag(ref const Deb[] debs) {
    DebNames[string] namesForTag;
    StringSet allTags;
    foreach (deb; debs) {
        foreach (tag; deb.tags) {
            allTags.add(tag);
            if (auto debnames = deb.section in namesForTag)
                debnames.add(deb.name);
            else
                namesForTag[tag] = DebNames(deb.name);
        }
    }
    return SetAndAA(allTags, namesForTag);
}

string cacheFilename() {
    import std.datetime.systime: Clock;
    import std.file: tempDir;
    import std.path: buildPath;

    auto today = Clock.currTime;
    return tempDir.buildPath(
        "debfind-" ~ today.toISOExtString()[0..10] ~ ".cache");
}

private State getState(string line) {
    switch (line) {
        case DEB_FOR_NAME: return State.Debs;
        case NAMES_FOR_STEMMED_DESCRIPTION: return State.Descriptions;
        case NAMES_FOR_STEMMED_NAME: return State.Names;
        case NAMES_FOR_KIND: return State.Kinds;
        case NAMES_FOR_SECTION: return State.Sections;
        case NAMES_FOR_TAG: return State.Tags;
        default: return State.Unknown;
    }
}

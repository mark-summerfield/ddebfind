// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

import aaset: AAset;
import qtrac.debfind.deb: Deb, Kind;

private {
    import std.typecons: Tuple;

    enum PACKAGE_DIR = "/var/lib/apt/lists";
    enum PACKAGE_PATTERN = "*Packages";

    alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                 bool, "ok");
    alias DebNames = AAset!string;
    struct IndexedMessage {}
}

struct Model {
    private {
        Deb[string] debForName;
        DebNames[string] namesForStemmedWord;
        int maxDebNamesForStemmedWord;
        DebNames[string] namesForStemmedName;
        DebNames[Kind] namesForKind;
        DebNames[string] namesForSection;
        DebNames[string] namesForTag;
        AAset!string allTags;
    }

    this(int maxDebNamesForStemmedWord) {
        this.maxDebNamesForStemmedWord = maxDebNamesForStemmedWord;
    }

    size_t length() const { return debForName.length; }

    version(unittest) {
        import std.stdio: write, writeln;
        void dumpDebs() {
            foreach (deb; debForName)
                writeln(deb);
        }
        void dumpStemmedWordIndex() {
            import std.range: empty;
            foreach (word, names; namesForStemmedWord) {
                write(word, ":");
                foreach (name; names)
                    write(" ", name);
                writeln;
            }
        }
    }

    // TODO
    //DebNames query(???) const {
    //}

    void readPackages(void delegate(bool) onReady) {
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
            onReady(false);
            makeIndexes;
            onReady(true);
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read packages: ", err);
        }
    }

    private void makeIndexes() {
        import std.array: array;
        import std.parallelism: task;

        const debs = debForName.byValue.array;
        auto stemmedWordsTask = task!makeNamesForStemmedWord(
            debs, maxDebNamesForStemmedWord);
        stemmedWordsTask.executeInNewThread;
        auto stemmedNamesTask = task!makeNamesForStemmedName(debs);
        stemmedNamesTask.executeInNewThread;
        auto kindsTask = task!makeNamesForKind(debs);
        kindsTask.executeInNewThread;
        auto sectionsTask = task!makeNamesForSection(debs);
        sectionsTask.executeInNewThread;

        foreach (deb; debs) {
            foreach (tag; deb.tags) {
                updateIndex(namesForTag, tag, deb.name);
                allTags.add(tag);
            }
        }

        namesForSection = sectionsTask.yieldForce;
        namesForKind = kindsTask.yieldForce;
        namesForStemmedName = stemmedNamesTask.yieldForce;
        namesForStemmedWord = stemmedWordsTask.yieldForce;
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
            deb.size = value.to!int;
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

    auto nonLetterRx = ctRegex!(`\P{L}+`);
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

private auto makeNamesForStemmedWord(ref const Deb[] debs,
                                     int maxDebNamesForStemmedWord) {
    import std.string: empty;

    AAset!string commonWords;
    DebNames[string] namesForStemmedWord;
    foreach (deb; debs) {
        foreach (word; stemmedWords(deb.description))
            if (!word.empty && word !in commonWords) {
                updateIndex(namesForStemmedWord, word, deb.name);
                if (namesForStemmedWord[word].length >
                    maxDebNamesForStemmedWord) {
                    commonWords.add(word);
                    namesForStemmedWord.remove(word);
                }
            }
    }
    return namesForStemmedWord;
}

private auto makeNamesForStemmedName(ref const Deb[] debs) {
    import std.string: empty;

    DebNames[string] namesForStemmedName;
    foreach (deb; debs) {
        foreach (word; stemmedWords(deb.name))
            if (!word.empty)
                updateIndex(namesForStemmedName, word, deb.name);
    }
    return namesForStemmedName;
}

private auto makeNamesForKind(ref const Deb[] debs) {
    DebNames[Kind] namesForKind;
    foreach (deb; debs) {
        if (auto debnames = deb.kind in namesForKind)
            debnames.add(deb.name);
        else
            namesForKind[deb.kind] = DebNames(deb.name);
    }
    return namesForKind;
}

private auto makeNamesForSection(ref const Deb[] debs) {
    DebNames[string] namesForSection;
    foreach (deb; debs)
        updateIndex(namesForSection, deb.section, deb.name);
    return namesForSection;
}

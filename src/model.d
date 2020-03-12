// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

import qtrac.debfind.common: unit, Unit;
import qtrac.debfind.deb: Deb, Kind;
import std.typecons: Tuple;

enum PACKAGE_DIR = "/var/lib/apt/lists";
enum PACKAGE_PATTERN = "*Packages";

private alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                     bool, "ok");
struct Model {
    private {
        Deb[string] debForName;
        string[][string] namesForStemmedWord;
        int maxDebNamesForStemmedWord;
        string[][string] namesForStemmedName;
        string[][Kind] namesForKind;
        //string[][string] namesForSection;
        //string[][tag] namesForTag;
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

            if (namesForStemmedWord.empty)
                populateNamesForStemmedWord;
            foreach (word, names; namesForStemmedWord) {
                write(word, ":");
                foreach (name; names)
                    write(" ", name);
                writeln;
            }
        }
    }

    /// Returns package names whose description contains all of the
    /// (stemmed) words.
    auto namesForAllWords(string words) {
        import std.algorithm: filter, map, sort, uniq;
        import std.array: array, byPair;
        import std.range: empty;

        if (namesForStemmedWord.empty)
            populateNamesForStemmedWord;
        size_t[string] debNames;
        auto stemmed = stemmedWords(words).array;
        size_t wordCount = stemmed.length;
        foreach (word; stemmed)
            if (auto names = word in namesForStemmedWord)
                foreach (name; *names)
                    debNames[name]++;
        return map!(pair => pair.key)
                   (filter!(pair => pair.value == wordCount)
                           (debNames.byPair)).array.sort.uniq;
    }

    /// Returns package names whose description contains any of the
    /// (stemmed) words.
    auto namesForAnyWords(string words) {
        import std.algorithm: sort, uniq;
        import std.range: empty;

        if (namesForStemmedWord.empty)
            populateNamesForStemmedWord;
        string[] result;
        foreach (word; stemmedWords(words))
            if (auto names = word in namesForStemmedWord)
                result ~= *names;
        return result.sort.uniq;
    }

    /// Returns package names whose name contains all of the
    /// (stemmed) words.
    auto namesForAllNames(string names) {
        import std.algorithm: filter, map, sort, uniq;
        import std.array: array, byPair;
        import std.range: empty;

        if (namesForStemmedName.empty)
            populateNamesForStemmedName;
        size_t[string] debNames;
        auto stemmed = stemmedWords(names).array;
        size_t wordCount = stemmed.length;
        foreach (word; stemmed)
            if (auto stemmedNames = word in namesForStemmedName)
                foreach (name; *stemmedNames)
                    debNames[name]++;
        return map!(pair => pair.key)
                   (filter!(pair => pair.value == wordCount)
                           (debNames.byPair)).array.sort.uniq;
    }

    /// Returns package names whose name contains any of the
    /// (stemmed) words.
    auto namesForAnyNames(string names) {
        import std.algorithm: sort, uniq;
        import std.array: array;
        import std.range: empty;

        if (namesForStemmedName.empty)
            populateNamesForStemmedName;
        string[] found;
        foreach (stemmed; stemmedWords(names)) {
            if (auto foundNames = stemmed in namesForStemmedName)
                foreach (name; *foundNames)
                    found ~= name;
        }
        return found.sort.uniq;
    }

    auto namesForAllKinds(Kind[] kinds ...) {
        import std.range: empty;

        if (namesForKind.empty)
            populateNamesForKind;
        // TODO use namesForAll(T, U)(namesForKind, kinds)
    }

    auto namesForAnyKind(Kind[] kinds ...) {
        import std.range: empty;

        if (namesForKind.empty)
            populateNamesForKind;
        // TODO use namesForAny(T, U)(namesForKind, kinds)
    }

    void readPackages(void delegate() onReady) {
        import std.file: dirEntries, FileException, SpanMode;

        try {
            foreach (string filename; dirEntries(PACKAGE_DIR,
                                                 PACKAGE_PATTERN,
                                                 SpanMode.shallow))
                readPackageFile(filename);
            onReady();
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read packages: ", err);
        }
    }

    private void readPackageFile(string filename) {
        import std.file: FileException;
        import std.range: enumerate;
        import std.stdio: File, stderr;

        try {
            bool inDescription = false; // Descriptions can by multi-line
            bool inContinuation = false; // Other things can be multi-line
            Deb deb;
            auto file = File(filename);
            foreach(lino, line; file.byLine.enumerate(1))
                readPackageLine(line, deb, inDescription, inContinuation);
            if (deb.valid)
                debForName[deb.name] = deb.dup;
        } catch (FileException err) {
            stderr.writefln("error: %s: failed to read packages: %s",
                            filename, err);
        }
    }

    private void readPackageLine(const(char[]) line, ref Deb deb,
                                 ref bool inDescription,
                                 ref bool inContinuation) {
        import std.string: empty, startsWith, strip;

        if (strip(line).empty) {
            if (deb.valid)
                debForName[deb.name] = deb.dup;
            deb.clear;
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

    private void populateNamesForStemmedWord() {
        import std.string: empty;

        Unit[string] commonWords;
        foreach (name, deb; debForName) {
            foreach (word; stemmedWords(deb.description)) {
                if (word.empty)
                    continue;
                if (word !in commonWords) {
                    namesForStemmedWord[word] ~= name;
                    if (namesForStemmedWord[word].length >
                            maxDebNamesForStemmedWord) {
                        commonWords[word] = unit;
                        namesForStemmedWord.remove(word);
                    }
                }
            }
        }
    }

    private void populateNamesForStemmedName() {
        import std.string: empty;

        foreach (name; debForName.byKey) {
            foreach (word; stemmedWords(name)) {
                if (word.empty)
                    continue;
                namesForStemmedName[word] ~= name;
            }
        }
    }

    private void populateNamesForKind() {
        // TODO
    }
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
        deb.tags[tag] = unit;
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

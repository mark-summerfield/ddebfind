// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

import qtrac.debfind.common: unit, Unit;
import qtrac.debfind.deb: Deb, Kind;
import std.typecons: Tuple;

enum PACKAGE_DIR = "/var/lib/apt/lists";
enum PACKAGE_PATTERN = "*Packages";

private alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                     bool, "ok");
private struct DoneMessage {}

struct Model {
    import std.concurrency: Tid;

    private {
        Deb[string] debForName;
        // set of deb names for each stemmed word from the Descriptions:
        string[][string] namesForWord;
        /* Possible other indexes:
        string[][Kind] _namesForKind;
        string[][string] _namesForSection;
        string[][tag] _namesForTag;
        */
        int maxDebNamesForWord;
    }

    this(int maxDebNamesForWord) {
        this.maxDebNamesForWord = maxDebNamesForWord;
    }

    size_t length() const { return debForName.length; }

    version(unittest) {
        auto debs() { return debForName.byValue; }
        auto words() { return namesForWord.byKey; }
        void dumpWordIndex() {
            import std.stdio: write, writeln;
            foreach (word, names; namesForWord) {
                write(word, ":");
                foreach (name; names)
                    write(" ", name);
                writeln;
            }
        }
    }

    auto namesForAnyWords(string words) const {
        import std.algorithm: sort, uniq;

        string[] result;
        foreach (word; normalizedWords(words))
            if (auto names = word in namesForWord)
                result ~= *names;
        return result.sort.uniq;
    }

    auto namesForAllWords(string words) const {
        import std.algorithm: filter, map, sort, uniq;
        import std.array: array, byPair;

        size_t[string] debNames;
        auto normalized = normalizedWords(words).array;
        size_t wordCount = normalized.length;
        foreach (word; normalized)
            if (auto names = word in namesForWord)
                foreach (name; *names)
                    debNames[name]++;
        return map!(pair => pair.key)
                   (filter!(pair => pair.value == wordCount)
                           (debNames.byPair)).array.sort.uniq;
    }

    void readPackages() {
        import std.concurrency: receive, thisTid, spawn;
        import std.file: dirEntries, FileException, SpanMode;

        Tid[] tids;
        try {
            foreach (string filename; dirEntries(PACKAGE_DIR,
                                                 PACKAGE_PATTERN,
                                                 SpanMode.shallow))
                tids ~= spawn(&readPackageFile, thisTid, filename);
            auto jobs = tids.length;
            while (jobs) {
                receive(
                    (Deb deb) { debForName[deb.name] = deb; },
                    (DoneMessage m) { jobs--; }
                );
            }
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read packages: ", err);
        }
    }

    private void readPackageFile(Tid parentTid, string filename) {
        import std.concurrency: send;
        import std.file: FileException;
        import std.range: enumerate;
        import std.stdio: File, stderr;

        try {
            bool inDescription = false; // Descriptions can by multi-line
            bool inContinuation = false; // Other things can be multi-line
            Deb deb;
            assert(!deb.valid);
            auto file = File(filename);
            foreach(lino, line; file.byLine.enumerate(1))
                readPackageLine(parentTid, filename, lino, line, deb,
                                inDescription, inContinuation);
            if (deb.valid)
                send(parentTid, cast(immutable)deb.dup);
        } catch (FileException err) {
            stderr.writefln("error: %s: failed to read packages: %s",
                            filename, err);
        }
        send(parentTid, DoneMessage());
    }

    private void readPackageLine(
            Tid parentTid, const string filename, const int lino,
            const(char[]) line, ref Deb deb, ref bool inDescription,
            ref bool inContinuation) {
        import std.concurrency: send;
        import std.path: baseName;
        import std.stdio: stderr;
        import std.string: empty, startsWith, strip;

        if (strip(line).empty) {
            if (deb.valid)
                send(parentTid, cast(immutable)deb.dup);
            else if (!deb.name.empty || !deb.section.empty ||
                        !deb.description.empty || !deb.tags.empty)
                stderr.writefln("error: %s:%,d: incomplete package: %s",
                                baseName(filename), lino, deb);
            deb.clear;
            assert(!deb.valid);
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
            inDescription = populateDeb(deb, keyValue.key,
                                        keyValue.value);
    }

    void populateIndexes() {
        import std.string: empty, split;

        Unit[string] commonWords;
        foreach (name, deb; debForName) {
            foreach (word; normalizedWords(deb.description)) {
                if (word.empty)
                    continue;
                if (word !in commonWords) {
                    namesForWord[word] ~= name;
                    if (namesForWord[word].length > maxDebNamesForWord) {
                        commonWords[word] = unit;
                        namesForWord.remove(word);
                    }
                }
                // TODO add to other indexes
            }
        }
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

private auto normalizedWords(const string line) {
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

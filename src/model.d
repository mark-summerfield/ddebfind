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
        Deb[string] debs; // AA of deb packages
        // set of deb names for each stemmed word from the Descriptions:
        Unit[string][string] namesForWord;
        int maxDebNamesForWord; // limit per-word AA size
        Unit[string] commonWords; // set of common words
        /* Possible other indexes:
        Unit[string][Kind] namesForKind; // huge trees?
        Unit[string][string] namesForSection; // huge trees?
        Unit[string][tag] namesForTag;
        */
    }

    size_t length() const {
        return debs.length;
    }

    void initialize(int maxDebNamesForWord) {
        import std.file: dirEntries, FileException, SpanMode;

        this.maxDebNamesForWord = maxDebNamesForWord;
        try {
            foreach (string name; dirEntries(PACKAGE_DIR, PACKAGE_PATTERN,
                                             SpanMode.shallow))
                readPackageFile(name);
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
            assert(!deb.valid);
            auto file = File(filename);
            foreach(lino, line; file.byLine.enumerate(1))
                readPackageLine(filename, lino, line, deb, inDescription,
                                inContinuation);
            if (deb.valid) {
                updateIndexes(deb);
                debs[deb.name] = deb;
            }
        } catch (FileException err) {
            stderr.writefln("error: %s: failed to read packages: %s",
                            filename, err);
        }
    }

    private void readPackageLine(
            string filename, int lino, const(char[]) line, ref Deb deb,
            ref bool inDescription, ref bool inContinuation) {
        import std.path: baseName;
        import std.stdio: stderr;
        import std.string: empty, startsWith, strip;

        if (strip(line).empty) {
            if (deb.valid) {
                updateIndexes(deb);
                debs[deb.name] = deb;
            }
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
        auto keyValue = maybeKeyValue(line);
        if (!keyValue.ok) 
            inContinuation = true;
        else
            inDescription = populateDeb(deb, keyValue.key,
                                        keyValue.value);
    }

    private void updateIndexes(ref Deb deb) {
        /* TODO
         namesForWord:
         - lowercase then split description
         - use the Porter stemming algorithm on each word
         - for each word only add if word not in commonWords and names <
           MAX_DEB_NAMES_FOR_WORD
         - drop entries where names > MAX_DEB_NAMES_FOR_WORD;
        */

        // don't add a word to namesForWord if is is in commonWords
        // if names in namesForWord >= MAX_DEB_NAMES_FOR_WORD then delete
        // that entry and add the word to commonWords
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

private bool populateDeb(ref Deb deb, string key, string value) {
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
        case "Description", "Npp-Description":
            deb.description ~= value;
            return true;
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

void maybeSetKindForName(ref Deb deb) {
    import std.string: startsWith;

    if (deb.kind is Kind.Unknown) {
        if (deb.name.startsWith("libreoffice"))
            deb.kind = Kind.GuiApp;
        else if (deb.name.startsWith("lib"))
            deb.kind = Kind.Library;
    }
}


void maybeSetKindForSection(ref Deb deb) {
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

void maybePopulateTags(ref Deb deb, string tags) {
    import std.regex: ctRegex, split;

    auto rx = ctRegex!(`\s*,\s*`);
    foreach (tag; tags.split(rx)) {
        deb.tags[tag] = unit;
        maybeSetKindForTag(deb, tag);
    }
}

void maybeSetKindForTag(ref Deb deb, string tag) {
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

void maybeSetKindForDepends(ref Deb deb, string depends) {
    import std.regex: ctRegex, matchFirst;

    auto rx = ctRegex!(`\blib(gtk|qt|tk|x11|fltk|motif|sdl|wx)|gnustep`);
    if (deb.kind is Kind.Unknown && matchFirst(depends, rx))
        deb.kind = Kind.GuiApp;
}

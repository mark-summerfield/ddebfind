// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.modelutil;

import qtrac.debfind.common: StringSet;
import qtrac.debfind.deb: Deb;
import qtrac.debfind.kind: Kind;

alias DebNames = StringSet;

enum TAB = "\t";
enum ITEM_SEP = "\v";
enum NL = "\n";
enum INDENT = "    ";
enum PREFIX = "@@INDEX=";
enum SUFFIX = "@@";
enum DEB_FOR_NAME = PREFIX ~ "debForName" ~ SUFFIX;
enum NAMES_FOR_STEMMED_DESCRIPTION = PREFIX ~
    "namesForStemmedDescription" ~ SUFFIX;
enum NAMES_FOR_STEMMED_NAME = PREFIX ~ "namesForStemmedName" ~ SUFFIX;
enum NAMES_FOR_KIND = PREFIX ~ "namesForKind" ~ SUFFIX;
enum NAMES_FOR_SECTION = PREFIX ~ "namesForSection" ~ SUFFIX;
enum NAMES_FOR_TAG = PREFIX ~ "namesForTag" ~ SUFFIX;
enum State { Unknown, Debs, Descriptions, Names, Kinds, Sections, Tags }

private {
    import std.typecons: Tuple;

    alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                 bool, "ok");
    alias SetAndAA = Tuple!(StringSet, "set", DebNames[string], "namesFor");
    alias SetAndKindAA = Tuple!(StringSet, "set", DebNames[Kind],
                                "namesFor");
}

Deb[] readPackageFile(string filename) {
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

auto stemmedWords(const string line) {
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
auto makeNamesForStemmedDescription(ref const Deb[] debs) {
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

auto makeNamesForStemmedName(ref const Deb[] debs) {
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

auto makeNamesForKind(ref const Deb[] debs) {
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

SetAndAA makeNamesForSection(ref const Deb[] debs) {
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

SetAndAA makeNamesForTag(ref const Deb[] debs) {
    DebNames[string] namesForTag;
    StringSet allTags;
    foreach (deb; debs) {
        foreach (tag; deb.tags) {
            allTags.add(tag);
            if (auto debnames = tag in namesForTag)
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

State getNextCachedState(string line) {
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

void readCachedDeb(string line, ref Deb[string] debForName,
                   ref StringSet allNames) {
    import qtrac.debfind.kind: fromString;
    import std.conv: ConvException, to;
    import std.stdio: stderr;
    import std.string: empty, replace, split;

    auto fields = line.split(TAB);
    if (fields.length == 8) {
        auto deb = Deb();
        deb.name = fields[0];
        deb.ver = fields[1];
        deb.section = fields[2];
        deb.url = fields[3];
        try {
            deb.size = fields[4].to!int;
        } catch (ConvException) {
            stderr.writeln("Deb invalid size (used 0): ", fields[4]);
        }
        deb.kind = fields[5].fromString;
        auto tags = fields[6];
        if (!tags.empty)
            foreach (tag; tags.split(ITEM_SEP))
                deb.tags.add(tag);
        deb.description = fields[7].replace(INDENT, TAB).replace(ITEM_SEP,
                                                                 NL);
        debForName[deb.name] = deb.dup;
    }
    else
        stderr.writeln("Deb invalid line: ", line);
}

void readCachedIndex(string line, ref DebNames[string] index) {
    import std.string: split;

    auto fields = line.split(TAB);
    if (fields.length == 2) {
        auto word = fields[0];
        foreach (name; fields[1].split(ITEM_SEP))
            updateIndex(index, word, name);
    }
}

void readCachedKind(string line, ref DebNames[Kind] namesForKind) {
    import qtrac.debfind.kind: fromString;
    import std.string: split;

    auto fields = line.split(TAB);
    if (fields.length == 2) {
        auto kind = fields[0].fromString;
        if (kind !is Kind.Unknown) {
            foreach (name; fields[1].split(ITEM_SEP)) {
                if (auto debnames = kind in namesForKind)
                    debnames.add(name);
                else
                    namesForKind[kind] = DebNames(name);
            }
        }
    }
}

void readCachedSection(string line, ref DebNames[string]namesForSection,
                       ref StringSet allSections) {
    import std.string: split;

    auto fields = line.split(TAB);
    if (fields.length == 2) {
        auto section = fields[0];
        foreach (name; fields[1].split(ITEM_SEP)) {
            allSections.add(section);
            if (auto debnames = section in namesForSection)
                debnames.add(name);
            else
                namesForSection[section] = DebNames(name);
        }
    }
}

void readCachedTags(string line, ref DebNames[string] namesForTag,
                    ref StringSet allTags) {
    import std.string: split;

    auto fields = line.split(TAB);
    if (fields.length == 2) {
        auto tag = fields[0];
        foreach (name; fields[1].split(ITEM_SEP)) {
            allTags.add(tag);
            if (auto debnames = tag in namesForTag)
                debnames.add(name);
            else
                namesForTag[tag] = DebNames(name);
        }
    }
}

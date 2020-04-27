// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.modelutil;

import qtrac.debfind.common: StringSet;
import qtrac.debfind.deb: Deb;

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
enum NAMES_FOR_SECTION = PREFIX ~ "namesForSection" ~ SUFFIX;
enum State { Unknown, Debs, Descriptions, Names, Sections }

alias NameAndDescription = Tuple!(string, "name", string, "description");

private {
    import std.typecons: Tuple;

    alias MaybeKeyValue = Tuple!(string, "key", string, "value",
                                 bool, "ok");
    alias SetAndAA = Tuple!(StringSet, "set", DebNames[string], "namesFor");
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
            return false;
        case "Version":
            deb.ver = value;
            return false;
        case "Section":
            deb.section = value;
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
        default: return false; // Ignore "uninteresting" fields
    }
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

SetAndAA makeNamesForStemmedName(ref const Deb[] debs) {
    import qtrac.debfind.common: COMMON_STEMS;
    import std.string: empty;

    DebNames[string] namesForStemmedName;
    StringSet allNames;
    foreach (deb; debs) {
        allNames.add(deb.name);
        foreach (word; stemmedWords(deb.name))
            if (!word.empty && word !in COMMON_STEMS)
                updateIndex(namesForStemmedName, word, deb.name);
    }
    return SetAndAA(allNames, namesForStemmedName);
}

SetAndAA makeNamesForSection(ref const Deb[] debs) {
    DebNames[string] namesForSection;
    StringSet allSections;
    foreach (deb; debs) {
        immutable section = genericSection(deb.section);
        allSections.add(section);
        if (auto debnames = section in namesForSection)
            debnames.add(deb.name);
        else
            namesForSection[section] = DebNames(deb.name);
    }
    return SetAndAA(allSections, namesForSection);
}

string genericSection(string section) pure {
    import std.string: lastIndexOf;
    immutable index = section.lastIndexOf('/');
    return (index > -1) ? section[index + 1..$] : section;
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
        case NAMES_FOR_SECTION: return State.Sections;
        default: return State.Unknown;
    }
}

void readCachedDeb(string line, ref Deb[string] debForName,
                   ref StringSet allNames) {
    import std.conv: ConvException, to;
    import std.stdio: stderr;
    import std.string: empty, replace, split;

    auto fields = line.split(TAB);
    if (fields.length == 6) {
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
        deb.description = fields[5].replace(INDENT, TAB).replace(ITEM_SEP,
                                                                 NL);
        debForName[deb.name] = deb.dup;
        allNames.add(deb.name);
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

void readCachedSection(string line, ref DebNames[string]namesForSection,
                       ref StringSet allSections) {
    import std.string: split;

    auto fields = line.split(TAB);
    if (fields.length == 2) {
        auto debSection = fields[0];
        foreach (name; fields[1].split(ITEM_SEP)) {
            immutable section = genericSection(debSection);
            allSections.add(section);
            if (auto debnames = section in namesForSection)
                debnames.add(name);
            else
                namesForSection[section] = DebNames(name);
        }
    }
}

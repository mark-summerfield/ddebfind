// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.query;

struct Query {
    import qtrac.debfind.common: StringSet;

    string section; // empty → ignore
    string descriptionWords; // empty → ignore
    bool matchAnyDescriptionWord; // false → match All
    string nameWords; // empty → ignore
    bool matchAnyNameWord; // false → match All
    bool includeLibraries;

    void clear() {
        section = "";
        descriptionWords = "";
        matchAnyDescriptionWord = false;
        nameWords = "";
        matchAnyNameWord = false;
        includeLibraries = false;
    }

    string toString() const pure {
        import std.format: format;
        return format("section=%s desc=\"%s\"%s name=\"%s\"%s%s",
                      section,
                      descriptionWords,
                      (matchAnyDescriptionWord ? "Any" : "All"),
                      nameWords,
                      (matchAnyNameWord ? "Any" : "All"),
                      (includeLibraries ? " Lib" : ""));
    }
}

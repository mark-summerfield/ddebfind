// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.query;

struct Query {
    import qtrac.debfind.common: StringSet;
    import qtrac.debfind.deb: Kind;

    string section; // empty → ignore
    string descriptionWords; // empty → ignore
    bool matchAnyDescriptionWord; // false → match All
    string nameWords; // empty → ignore
    bool matchAnyNameWord; // false → match All
    Kind kind = Kind.Any; // Kind.Any → ignore
    string tag; // empty → ignore

    void clear() {
        section = "";
        descriptionWords = "";
        matchAnyDescriptionWord = false;
        nameWords = "";
        matchAnyNameWord = false;
        kind = Kind.Any;
        tag = "";
    }
}

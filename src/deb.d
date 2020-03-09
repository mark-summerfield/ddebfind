// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

enum Kind {ConsoleApp, GuiApp, Library, Font, Data, Documentation, Unknown}

struct Deb {
    import qtrac.debfind.common: unit, Unit;

    string name;
    string ver;
    string section;
    string description;
    string url;
    Unit[string] tags; // set of tags
    int size = 0; // installed size (not package size)
    Kind kind = Kind.Unknown;

    Deb dup() const {
        Deb deb;
        deb.name = name;
        deb.ver = ver;
        deb.section = section;
        deb.description = description;
        deb.url = url;
        foreach (key; tags.byKey)
            deb.tags[key] = unit;
        deb.size = size;
        deb.kind = kind;
        return deb;
    }

    bool valid() {
        import std.string: empty;
        return !(name.empty || description.empty);
    }

    void clear() {
        name = "";
        ver = "";
        section = "";
        description = "";
        url = "";
        tags.clear;
        size = 0;
        kind = Kind.Unknown;
    }
}

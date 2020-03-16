// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

enum Kind {Any, ConsoleApp, GuiApp, Library, Font, Data, Documentation,
           Unknown}

struct Deb {
    import qtrac.debfind.common: StringSet;

    string name;
    string ver;
    string section;
    string description;
    string url;
    StringSet tags;
    size_t size = 0; // installed size (not package size)
    Kind kind = Kind.Unknown;

    Deb dup() pure const {
        Deb deb;
        deb.name = name;
        deb.ver = ver;
        deb.section = section;
        deb.description = description;
        deb.url = url;
        foreach (key; tags)
            deb.tags.add(key);
        deb.size = size;
        deb.kind = kind;
        return deb;
    }

    bool valid() const {
        import std.string: empty;
        return !name.empty; // Some debs don't have any description
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

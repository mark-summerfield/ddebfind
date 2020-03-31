// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

struct Deb {
    import qtrac.debfind.common: StringSet;

    string name;
    string ver;
    string section;
    string description;
    string url;
    size_t size = 0; // installed size (not package size)

    Deb dup() pure const {
        Deb deb;
        deb.name = name;
        deb.ver = ver;
        deb.section = section;
        deb.description = description;
        deb.url = url;
        deb.size = size;
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
        size = 0;
    }
}

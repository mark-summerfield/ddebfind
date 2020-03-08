// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

enum Kind {ConsoleApp, GuiApp, Library, Font, Documentation, Unknown}

struct Deb {
    import qtrac.debfind.common: Unit;

    string name;
    string section;
    string description;
    Unit[string] tags; // set of tags
    int size = 0;
    Kind kind = Kind.Unknown;

    bool valid() {
        import std.string: empty;
        return !(name.empty || description.empty);
    }

    void clear() {
        name = "";
        section = "";
        description = "";
        tags.clear;
        size = 0;
        kind = Kind.Unknown;
    }
}

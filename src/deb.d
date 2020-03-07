// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

enum Kind {ConsoleApp, GuiApp, Library, Font, Documentation, Unknown}

struct Deb {
    import std.container.rbtree: RedBlackTree;

    string name;
    string section;
    string description;
    auto tags = new RedBlackTree!string;
    int size = 0;
    Kind kind = Kind.Unknown;

    bool valid() {
        import std.string: empty;
        return !(name.empty || description.empty);
    }

    void reset() {
        name = "";
        section = "";
        description = "";
        tags = new RedBlackTree!string;
        size = 0;
        kind = Kind.Unknown;
    }
}

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.deb;

enum Kind {ConsoleApp, GuiApp, Library, Font, Documentation, Unknown}

struct Deb {
    import std.container.rbtree: RedBlackTree;

    string name;
    string section;
    string description;
    RedBlackTree!string tags;
    int size = 0;
    Kind kind = Kind.Unknown;

    bool valid() {
        import std.string: empty;
        return !(name.empty || description.empty);
    }

    size_t toHash() const @safe nothrow {
        return typeid(name).getHash(&name); // names are unique
    }

    bool opEquals(const Deb other) const @safe pure nothrow {
        return name == other.name; // names are unique
    }

    int opCmp(ref const Deb other) const {
        import std.string: cmp;
        return cmp(name, other.name); // names are unique
    }
}

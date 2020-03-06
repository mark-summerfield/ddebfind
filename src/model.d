// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

enum PackageDir = "/var/lib/apt/lists";
enum PackagePattern = "*Packages";
enum Kind {ConsoleApp, GuiApp, Library, Font, Documentation, Unknown}

struct Package {
    string name;
    string ver;
    string section;
    string description;
    string[] tags;
    int size = 0;
    Kind kind = Kind.Unknown;
}

// If the user wants to limit by Kind we do it at the end because if we
// used a string[][Kind] it would have potentially thousands of names. The
// same applies to sections and tags.

struct Model {
    import std.container.rbtree: RedBlackTree;

    private {
        Package[string] packageForName;
        // stemmed words from splitting Descriptions:
        RedBlackTree!string[string] namesForWord;
        int maxPackageNamesForWord; // limit per-word tree size
        /* Possible other indexes:
        RedBlackTree!string[Kind] namesForKind; // huge trees?
        RedBlackTree!string[string] namesForSection; // huge trees?
        RedBlackTree!string[tag] namesForTag;
        */
    }

    void initialize(int maxPackageNamesForWord) {
        import std.file: dirEntries, FileException, SpanMode;

        this.maxPackageNamesForWord = maxPackageNamesForWord;
        try {
            foreach (string name; dirEntries(PackageDir, PackagePattern,
                                             SpanMode.shallow))
                readPackageFile(name);
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writeln("failed to read packages: ", err);
        }
    }

    private void readPackageFile(string filename) {
        import std.file: FileException;
        /* TODO
         namesForWord:
         - lowercase then split description
         - use the Porter stemming algorithm on each word
         - for each word only add if word not in commonWords and names <
           MaxPackageNamesForWord
         - drop entries where names > MaxPackageNamesForWord;
        */

        auto commonWords = new RedBlackTree!string;
        // don't add a word to namesForWord if is is in commonWords
        // if names in namesForWord >= MaxPackageNamesForWord then delete
        // that entry and add the word to commonWords
        try {
            // TODO
        } catch (FileException err) {
            import std.stdio: stderr;
            stderr.writefln("failed to read packages from %s: %s", filename,
                            err);
        }
import std.stdio: writeln; writeln(filename); // TODO delete

    }
}

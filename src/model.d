// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

enum PackageDir = "/var/lib/apt/lists";
enum PackagePattern = "*Packages";

struct Model {
    import qtrac.debfind.deb: Deb, Kind;
    import std.container.rbtree: RedBlackTree;

    private {
        // name-ordered list of deb packages
        RedBlackTree!(Deb, (a, b) => a.name < b.name) debs;
        // stemmed words from splitting Descriptions:
        RedBlackTree!string[string] namesForWord;
        int maxDebNamesForWord; // limit per-word tree size
        /* Possible other indexes:
        RedBlackTree!string[Kind] namesForKind; // huge trees?
        RedBlackTree!string[string] namesForSection; // huge trees?
        RedBlackTree!string[tag] namesForTag;
        */
    }

    void initialize(int maxDebNamesForWord) {
        import std.file: dirEntries, FileException, SpanMode;

        this.maxDebNamesForWord = maxDebNamesForWord;
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
        import std.stdio: File, stderr;
        import std.string: empty, strip;
        /* TODO
         namesForWord:
         - lowercase then split description
         - use the Porter stemming algorithm on each word
         - for each word only add if word not in commonWords and names <
           MAX_DEB_NAMES_FOR_WORD
         - drop entries where names > MAX_DEB_NAMES_FOR_WORD;
        */

        auto commonWords = new RedBlackTree!string;
        // don't add a word to namesForWord if is is in commonWords
        // if names in namesForWord >= MAX_DEB_NAMES_FOR_WORD then delete
        // that entry and add the word to commonWords
        try {
            bool inDeb = false;
            bool inDescription = false; // can by multi-line
            Deb deb;
            assert(!deb.valid);
            auto file = File(filename);
            foreach(line; file.byLine) {
                line = strip(line);
                if (line.empty) {
                    if (deb.valid)
                        debs.insert(deb);
                    else if (!deb.name.empty || !deb.section.empty ||
                             !deb.description.empty || !deb.tags.empty)
                        stderr.writeln("incomplete package: ", deb);
                    deb.clear;
                    assert(!deb.valid);
                    continue;
                }
                // TODO guess what Kind the deb is
                // TODO -- try to refactor
            }
            if (deb.valid)
                debs.insert(deb);
        } catch (FileException err) {
            stderr.writefln("failed to read packages from %s: %s", filename,
                            err);
        }
import std.stdio: writeln; writeln(filename); // TODO delete

    }
}

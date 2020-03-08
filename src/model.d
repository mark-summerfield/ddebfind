// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model;

enum PACKAGE_DIR = "/var/lib/apt/lists";
enum PACKAGE_PATTERN = "*Packages";

struct Model {
    import qtrac.debfind.common: unit, Unit;
    import qtrac.debfind.deb: Deb, Kind;

    private {
        // AA of deb packages
        Deb[string] debs;
        // set of deb names for each stemmed word from the Descriptions:
        Unit[string][string] namesForWord;
        int maxDebNamesForWord; // limit per-word AA size
        /* Possible other indexes:
        Unit[string][Kind] namesForKind; // huge trees?
        Unit[string][string] namesForSection; // huge trees?
        Unit[string][tag] namesForTag;
        */
    }

    void initialize(int maxDebNamesForWord) {
        import std.file: dirEntries, FileException, SpanMode;

        this.maxDebNamesForWord = maxDebNamesForWord;
        try {
            foreach (string name; dirEntries(PACKAGE_DIR, PACKAGE_PATTERN,
                                             SpanMode.shallow))
                readPackageFile(name);
// XXX TODO this is just to check they've been added before I use the GUI
// ought to replace with a simple count test in model_test.d XXX
import std.stdio: writeln;foreach (deb; debs) writeln(deb); // XXX TODO
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

        Unit[string] commonWords; // set of common words
        // don't add a word to namesForWord if is is in commonWords
        // if names in namesForWord >= MAX_DEB_NAMES_FOR_WORD then delete
        // that entry and add the word to commonWords
        try {
            bool inDescription = false; // can by multi-line
            Deb deb;
            assert(!deb.valid);
            auto file = File(filename);
            foreach(line; file.byLine) {
                line = strip(line);
                if (line.empty) {
                    if (deb.valid)
                        debs[deb.name] = deb;
                    else if (!deb.name.empty || !deb.section.empty ||
                             !deb.description.empty || !deb.tags.empty)
                        stderr.writeln("incomplete package: ", deb);
                    deb.clear;
                    assert(!deb.valid);
                    continue;
                }
                //if (!inDescription)
                    // TODO split on first ';' etc.
                    // if (name.startsWith("libreoffice")
                    //     kind = Kind.Gui;
                    // else if (name.startsWith("lib")
                    //     kind = Kind.Library;
                    // etc...
                //else {
                //    // TODO
                //}
                // TODO guess what Kind the deb is
                // TODO -- try to refactor
            }
            if (deb.valid)
                debs[deb.name] = deb;
        } catch (FileException err) {
            stderr.writefln("failed to read packages from %s: %s", filename,
                            err);
        }
import std.stdio: writeln; writeln(filename); // TODO delete

    }
}

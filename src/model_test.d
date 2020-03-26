// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import core.runtime: Runtime;
    import qtrac.debfind.common: decSecs, StringSet;
    import qtrac.debfind.model: Model;
    import qtrac.debfind.query: Query;
    import std.algorithm: canFind, sort;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: stderr, write, writeln;
    import std.string: empty, endsWith;

    stderr.writeln("reading package files…");
    auto model = Model();
    auto timer = StopWatch(AutoStart.yes);
    model.readPackages(delegate void(bool done, size_t fileCount) {
        auto secs = decSecs(timer.peek);
        if (!done)
            stderr.writefln("read %,d package files in %0.1f secs; " ~
                            "indexing…", fileCount, secs);
        else
            stderr.writefln("read %,d package files and indexed %,d " ~
                            "packages in %0.1f secs.", fileCount,
                            model.length, secs);
    });
    const args = Runtime.args()[1..$];
    if (!args.empty) {
        if (args[0].endsWith(".csv")) {
            model.dumpCsv(args[0]);
        } else switch (args[0]) {
            case "d": model.dumpDebs; break;
            case "w": model.dumpStemmedDescriptionIndex; break;
            default: break;
        }
        return;
    }

    void report(const StringSet names, int max=50) {
        auto nameList = names.array;
        write("*** deb names:");
        if (nameList.length > max) {
            write(' ', nameList.length, " including:");
            nameList = nameList[0..max];
        }
        foreach (name; nameList.sort)
            write(' ', name);
        writeln;
    }

    void check(const StringSet names, const StringSet mustInclude,
               int min=1, int max=int.max) {
        assert(names.length >= min && names.length <= max);
        if (!mustInclude.empty)
            assert((names & mustInclude) == mustInclude);
    }

    Query query;
    StringSet names;

    query.clear;
    query.section = "vcs";
    names = model.query(query);
    check(names, StringSet("git"), 2);

    query.clear;
    query.descriptionWords = "haskell numbers";
    names = model.query(query); // All
    check(names, StringSet("libghc-random-dev"), 2);

    query.clear;
    query.descriptionWords = "haskell numbers";
    query.matchAnyDescriptionWord = true;
    names = model.query(query); // Any
    check(names, StringSet("libghc-random-dev", "haskell-doc",
                           "libghc-strict-dev"), 800);

    query.clear;
    query.descriptionWords = "haskell daemon";
    names = model.query(query); // All
    check(names, StringSet("hdevtools"), 1, 1);

    query.clear;
    query.descriptionWords = "haskell daemon";
    query.matchAnyDescriptionWord = true;
    names = model.query(query); // Any
    check(names, StringSet("libghc-random-dev", "haskell-doc",
                           "libghc-strict-dev"), 1000);
//    report(names);

    // desc any
    // desc all
    // name any
    // name all
    // kind
    // tag
    // TODO test single attribute queries

    // section + desc any
    // section + desc all
    // section + name any
    // section + name all
    // kind + desc any
    // kind + desc all
    // kind + name any
    // kind + name all
    // tag + desc any
    // tag + desc all
    // tag + name any
    // tag + name all
    // TODO test multiple attribute queries
}

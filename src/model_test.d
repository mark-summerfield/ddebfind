// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import core.runtime: Runtime;
    import qtrac.debfind.common: decSecs, MAX_DEB_NAMES_FOR_WORD, StringSet;
    import qtrac.debfind.model: Model;
    import qtrac.debfind.query: Query;
    import std.algorithm: canFind, sort;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: stderr, writeln;
    import std.string: empty, endsWith;

    stderr.writeln("reading package files…");
    auto model = Model(MAX_DEB_NAMES_FOR_WORD);
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
            case "w": model.dumpStemmedWordIndex; break;
            default: break;
        }
        return;
    }

    void report(const StringSet names) {
        foreach (name; names.array.sort) {
            writeln(name);
        }
    }

    void check(const StringSet names, int min, int max,
               const StringSet mustInclude) {
        assert(names.length >= min && names.length <= max);
        if (!mustInclude.empty)
            assert((names & mustInclude) == mustInclude);
    }

    Query query;
    query.section = "vcs";
    auto names = model.query(query);
    check(names, 2, int.max, StringSet("git"));

    query.clear;

    // TODO more model.query() tests ...
}

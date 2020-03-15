// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: decSecs, MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.algorithm: canFind;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: writeln;
    import std.string: empty;

    writeln("reading package files…");
    auto model = Model(MAX_DEB_NAMES_FOR_WORD);
    auto timer = StopWatch(AutoStart.yes);
    model.readPackages(delegate void(bool done, size_t fileCount) {
        import std.stdio: writefln;
        auto secs = decSecs(timer.peek);
        if (!done)
            writefln("read %,d package files in %0.1f secs; indexing…",
                     fileCount, secs);
        else
            writefln("read %,d package files and indexed %,d packages " ~
                     "in %0.1f secs.", fileCount, model.length, secs);
    });
    if (auto dump = environment.get("DUMP")) {
        if (dump == "d")
            model.dumpDebs;
        else if (dump == "w")
            model.dumpStemmedWordIndex;
    }

    // TODO model.query() ...
}

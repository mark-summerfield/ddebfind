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

    writeln("model.d unittests #1");
    auto model = Model(MAX_DEB_NAMES_FOR_WORD);
    auto timer = StopWatch(AutoStart.yes);
    model.readPackages(delegate void(bool done) {
        import std.stdio: writefln;
        auto secs = decSecs(timer.peek);
        if (!done)
            writefln("read packages in %0.1f secs; indexing…", secs);
        else
            writefln("read and indexed %,d packages in %0.1f secs.",
                     model.length, secs);
    });
    if (auto dump = environment.get("DUMP")) {
        if (dump == "d")
            model.dumpDebs;
        else if (dump == "w")
            model.dumpStemmedWordIndex;
    }

    // TODO model.query() ...
}

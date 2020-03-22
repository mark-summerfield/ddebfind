// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: decSecs, MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.algorithm: canFind;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: stderr;
    import std.string: empty;

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
    if (auto dump = environment.get("DUMP")) {
        switch (dump) {
            case "c": model.dumpCsv; break;
            case "d": model.dumpDebs; break;
            case "w": model.dumpStemmedWordIndex; break;
            default: break;
        }
    }

    // TODO model.query() ...
}

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: writeln;
    import std.string: empty;

    writeln("model.d unittests #1");
    auto model = Model(MAX_DEB_NAMES_FOR_WORD);
    auto timer = StopWatch(AutoStart.yes);
    model.readPackages(delegate void() {
        import std.stdio: writefln;
        writefln("read %,d packages in %s", model.length, timer.peek);
    });
    if (auto dump = environment.get("DUMP"))
        if (dump == "1")
            model.dumpDebs;
    //model.dumpWordIndex;

    auto names = model.namesForAnyWords("vim").array;

    assert(names.length > 20);
    names = model.namesForAnyWords("zig zag").array;
    assert(names.empty);
    names = model.namesForAnyWords("zig zag libreoffice").array;
    assert(names.length > 40);
    names = model.namesForAnyWords("note take").array;
    assert(names.length > 5);

    names = model.namesForAllWords("vim").array;
    assert(names.length > 20);
    names = model.namesForAllWords("zig zag").array;
    assert(names.empty);
    names = model.namesForAllWords("zig zag libreoffice").array;
    assert(names.empty);
    names = model.namesForAllWords("note take").array;
    assert(names.length > 5);
}

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.stdio: writeln, writefln;
    import std.string: empty;

    writeln("model.d unittests #1");
    Model model;
    auto timer = StopWatch(AutoStart.yes);
    model.initialize(MAX_DEB_NAMES_FOR_WORD);
    writefln("read %,d packages in %s", model.length, timer.peek);
    //foreach (deb; model.debs) writeln(deb);
    //foreach (word; model.words) writeln(word);

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

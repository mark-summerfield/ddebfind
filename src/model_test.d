// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.stdio: writeln, writefln;
    import std.string: empty;

    writeln("model.d unittests #1");
    Model model;
    auto timer = StopWatch(AutoStart.yes);
    model.initialize(MAX_DEB_NAMES_FOR_WORD);
//    foreach (deb; model.debs) writeln(deb);
    writefln("read %,d packages in %s", model.length, timer.peek);
    auto names = model.namesForAnyWords("vim");
    assert(names.length > 20);
    names = model.namesForAnyWords("zig zag");
    assert(names.empty);
    names = model.namesForAnyWords("zig zag libreoffice");
    assert(names.length > 40);
    names = model.namesForAllWords("vim");
    assert(names.length > 20);
    names = model.namesForAllWords("zig zag");
    assert(names.empty);
    names = model.namesForAllWords("zig zag libreoffice");
    assert(names.empty);
    names = model.namesForAllWords("note take");
    assert(names.length > 5);
}

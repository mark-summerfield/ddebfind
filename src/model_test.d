// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
    import qtrac.debfind.model: Model;
    import std.stdio: writeln, writefln;

    writeln("model.d unittests #1");
    Model model;
    model.initialize(MAX_DEB_NAMES_FOR_WORD);
    writefln("read %,d packages", model.length);
}

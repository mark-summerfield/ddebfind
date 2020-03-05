// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    // import qtrac.debfind.model: ??? ;
    import std.stdio: writeln;

    writeln("model.d unittests #1");

    import stemmer: Stemmer;

    auto stemmer = new Stemmer;

    void check(string original, string expeced) {
        const word = stemmer.stem(original);
        assert(word == expeced);
    }

    check("alarmed", "alarm");
    check("options", "option");
    check("meeting", "meet");
}

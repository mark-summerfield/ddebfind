// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    // import qtrac.debfind.model: ??? ;
    import std.stdio: writeln;

    writeln("model.d unittests #1");

    import stemmer: Stemmer;

    auto stemmer = new Stemmer;

    void check(string original) {
        auto word = stemmer.stem(original);
        writeln(original, "→", word);
    }

    check("alarmed");
    check("options");
    check("meeting");
}

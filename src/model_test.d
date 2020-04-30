// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.model_test;

unittest {
    import core.runtime: Runtime;
    import qtrac.debfind.common: decSecs, StringSet;
    import qtrac.debfind.model: Model;
    import qtrac.debfind.query: Query;
    import std.algorithm: canFind, sort;
    import std.array: array;
    import std.datetime.stopwatch: AutoStart, StopWatch;
    import std.process: environment;
    import std.stdio: stderr, write, writefln, writeln;
    import std.string: empty, endsWith;

    stderr.writeln("Reading package files…");
    auto model = Model();
    auto timer = StopWatch(AutoStart.yes);

    auto onReady = delegate void(bool done, size_t fileCount) {
        auto secs = decSecs(timer.peek);
        if (!done)
            stderr.writefln("Read %,d package files in %0.1f secs; " ~
                            "indexing…", fileCount, secs);
        else {
            if (!fileCount)
                stderr.writefln("Read cached data for %,d packages " ~
                                "in %0.1f secs.", model.length, secs);
            else
                stderr.writefln("Read %,d package files and indexed %,d " ~
                                "packages in %0.1f secs.", fileCount,
                                model.length, secs);
        }
    };
    model.readPackages(onReady);

    bool moreToDo;
    bool refresh;
    bool extraOutput;
    const args = Runtime.args()[1..$];
    if (!args.empty) {
        if (args[0].endsWith(".csv")) {
            model.dumpCsv(args[0]);
        } else switch (args[0]) {
            case "a": model.dumpAlls; break;
            case "d": model.dumpDebs; break;
            case "n": model.dumpStemmedNameIndex; break;
            case "s": model.dumpSectionIndex; break;
            case "r": refresh = true; moreToDo = true; break;
            case "x": extraOutput = true; moreToDo = true; break;
            case "w": model.dumpStemmedDescriptionIndex; break;
            default: break;
        }
        if (!moreToDo)
            return;
    }

    void report(string what, const StringSet names, int max=50) {
        auto nameList = names.array;
        write("*** ", what, " deb names:");
        if (nameList.length > max) {
            write(' ', nameList.length, " including:");
            nameList = nameList[0..max];
        }
        foreach (name; nameList.sort)
            write(' ', name);
        writeln;
    }

    void check(const StringSet names, const StringSet mustInclude,
               int min=1, int max=int.max, size_t lino=__LINE__) {
        import std.conv: to;

        assert(names.length >= min && names.length <= max,
               lino.to!string ~ ": checK: wrong length " ~
               names.length.to!string);
        if (!mustInclude.empty)
            assert((names & mustInclude) == mustInclude,
                   lino.to!string ~ ": checK: wrong/missing name(s)");
    }

    void runTests() {
        writeln("runTests");

        Query query;
        StringSet names;

        query.clear;
        query.descriptionWords = "haskell numbers";
        query.includeLibraries = true;
        names = model.query(query); // All
        check(names, StringSet("libghc-random-dev"), 2);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.descriptionWords = "haskell numbers";
        query.matchAnyDescriptionWord = true;
        query.includeLibraries = true;
        names = model.query(query); // Any
        check(names, StringSet("libghc-random-dev", "haskell-doc",
                            "libghc-strict-dev"), 800);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.descriptionWords = "haskell daemon";
        names = model.query(query); // All
        check(names, StringSet("hdevtools"), 1, 1);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.descriptionWords = "haskell daemon";
        query.matchAnyDescriptionWord = true;
        query.includeLibraries = true;
        names = model.query(query); // Any
        check(names, StringSet("libghc-random-dev", "haskell-doc",
                            "libghc-strict-dev"), 1000);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "python";
        names = model.query(query); // All
        query.nameWords = "python3";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet("python3"), 2000);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "python django";
        names = model.query(query); // All
        query.nameWords = "python3 django";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet(
            "python3-ajax-select", "python3-dj-static", "python3-django",
            "python3-django-captcha", "python3-django-compressor",
            "python3-django-environ", "python3-django-imagekit",
            "python3-django-memoize", "python3-django-rules",
            "python3-django-uwsgi", "python3-django-xmlrpc",
            "python3-djangorestframework", "python3-pylint-django",
            "python3-pytest-django"), 100);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "python django memoize";
        names = model.query(query); // All
        query.nameWords = "python3 django memoize";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet("python3-django-memoize"), 1, 1);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "python django memoize";
        query.matchAnyNameWord = true;
        names = model.query(query); // Any
        query.nameWords = "python3 django memoize";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet(
            "python-django-app-plugins", "python3-affine", "python3-distro",
            "python3-distutils", "python3-gdbm", "python3-pyx",
            "python3-requests-mock", "python3-sklearn-lib",
            "python3-sparse", "python3-yaml", "python3-django-memoize"),
                2500);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "vcs";
        names = model.query(query);
        check(names, StringSet("git"), 2);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "math";
        names = model.query(query);
        check(names, StringSet("bc", "dc", "lp-solve"), 3);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "math";
        query.includeLibraries = true;
        names = model.query(query);
        check(names, StringSet("bc", "dc", "lp-solve"), 3);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "python";
        query.includeLibraries = true;
        names = model.query(query);
        check(names, StringSet("libpython-dev"), 10);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "python";
        query.nameWords = "python";
        names = model.query(query); // All
        query.nameWords = "python3";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet("python3"), 200);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "python";
        query.nameWords = "python django";
        names = model.query(query); // All
        query.nameWords = "python3 django";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet("python3-django"), 2);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "python";
        query.nameWords = "python django memoize";
        names = model.query(query); // All
        query.nameWords = "python3 django memoize";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet(), 0, 1);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.section = "python";
        query.nameWords = "python django memoize";
        query.matchAnyNameWord = true;
        names = model.query(query); // Any
        query.nameWords = "python3 django memoize";
        assert(names == model.query(query)); // python is special-cased
        check(names, StringSet(
            "python3-django", "python3-all", "python3-debian",
            "python3-distutils", "python3-gdbm", "python3-requests",
            "python3-yaml"), 200);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "memoize";
        names = model.query(query); // All
        assert(names.length > 10);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "memoize python";
        names = model.query(query); // All
        assert(names.length >= 2);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "memoize python django";
        names = model.query(query); // All
        assert(names.length >= 1);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "python django";
        query.matchAnyNameWord = true;
        names = model.query(query); // Any
        assert(names.length >= 2_500);
        if (extraOutput) writefln("%8,d names %s", names.length, query);

        query.clear;
        query.nameWords = "zzzzzz";
        names = model.query(query); // All
        assert(names.length == 0);
        if (extraOutput) writefln("%8,d names %s", names.length, query);
    }

    runTests();
    if (refresh) {
        model.refresh(onReady);
        runTests();
    }
}

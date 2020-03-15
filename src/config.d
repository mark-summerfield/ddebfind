// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.config;

static Config config; // Must call config.load(applicationId) before use

enum MIN_WINDOW_SIZE = 200;
enum MAX_WINDOW_SIZE = 2000;

private struct Config {
    import glib.KeyFile: KeyFile;
    import std.algorithm: clamp;

    int x() const { return m.x; }

    void x(const int x) {
        m.x = x;
    }

    int y() const { return m.y; }

    void y(const int y) {
        m.y = y;
    }

    bool xyIsValid() const { return m.x > INVALID && m.y > INVALID; }

    int width() const { return m.width; }

    void width(const int width) {
        m.width = clamp(width, MIN_WINDOW_SIZE, MAX_WINDOW_SIZE);
    }

    int height() const { return m.height; }

    void height(const int height) {
        m.height = clamp(height, MIN_WINDOW_SIZE, MAX_WINDOW_SIZE);
    }

    // Must be called before use of static
    void load(string applicationId) {
        import glib.GException: GException;
        import glib.Util: gutil = Util;
        import glib.c.types: GKeyFileFlags;
        import std.array: replace;
        import std.path: buildPath, dirSeparator;

        filename = buildPath(gutil.getUserConfigDir,
                             applicationId.replace('.',
                                                   dirSeparator) ~ ".ini");
        auto keyFile = new KeyFile;
        bool ok;
        try {
            ok = keyFile.loadFromFile(filename,
                                      GKeyFileFlags.KEEP_COMMENTS);
        } catch (GException) {
            ok = false;
        }
        if (!ok) {
            import std.stdio: stderr;
            stderr.writeln("failed to load config: will use defaults");
            return;
        }
        x(get(keyFile, WINDOW, X, INVALID));
        y(get(keyFile, WINDOW, Y, INVALID));
        width(get(keyFile, WINDOW, WIDTH, DEF_WIDTH));
        height(get(keyFile, WINDOW, HEIGHT, DEF_HEIGHT));
    }

    private T get(T)(ref KeyFile keyFile, string group, string key,
                     const T defaultValue) {
        auto value = keyFile.getValue(group, key);
        if (value !is null) {
            import std.conv: ConvException, to;
            try {
                return value.to!T;
            } catch (ConvException) {
                // ignore and return default
            }
        }
        return defaultValue;
    }

    bool save() {
        assert(filename.length);

        import std.file: exists, FileException, mkdirRecurse;
        import std.path: dirName;

        immutable path = dirName(filename);
        if (!path.exists)
            try {
                mkdirRecurse(path);
            } catch (FileException err) {
                import std.stdio: stderr;
                stderr.writefln("failed to create config path: %s", err);
                return false;
            }
        auto keyFile = new KeyFile;
        keyFile.setInteger(WINDOW, X, x);
        keyFile.setInteger(WINDOW, Y, y);
        keyFile.setInteger(WINDOW, WIDTH, width);
        keyFile.setInteger(WINDOW, HEIGHT, height);
        if (!keyFile.saveToFile(filename)) {
            import std.stdio: stderr;
            stderr.writeln("failed to save config");
            return false;
        }
        return true;
    }

    private {
        enum WINDOW = "Window";
        enum X = "x";
        enum Y = "y";
        enum WIDTH = "width";
        enum HEIGHT = "height";

        enum DEF_WIDTH = 640;
        enum DEF_HEIGHT = 480;

        enum INVALID = -1;

        string filename;

        struct M {
            int x = INVALID;
            int y = INVALID;
            int width = DEF_WIDTH;
            int height = DEF_HEIGHT;
        }
        M m;
    }
}

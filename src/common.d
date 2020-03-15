// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.common;

import aaset: AAset;
import core.time: Duration;
import std.string: splitLines;

enum APPNAME = "DebFind";
enum VERSION = "v0.1.0";
static string[] ICON_XPM = splitLines(import("data/icon.dxpm"));
enum MAX_DEB_NAMES_FOR_WORD = 100; // TODO make this user-configurable

alias StringSet = AAset!string;

float decSecs(Duration duration) pure {
    auto t = duration.split!("seconds", "msecs");    
    return t.seconds + (t.msecs / 1000.0);
}

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.common;

import aaset: AAset;
import core.time: Duration;
import std.string: splitLines;

enum APPNAME = "DebFind";
enum VERSION = "v0.1.0";
static string[] ICON_XPM = splitLines(import("data/icon.dxpm"));

alias StringSet = AAset!string;

enum COMMON_STEMS = StringSet(
    "and", "applic", "bit", "compil", "data", "debug", "develop",
    "document", "file", "for", "gnu", "in", "kernel", "librari", "linux",
    "modul", "of", "on", "packag", "python", "runtim", "support", "the",
    "to", "tool", "version", "with");

float decSecs(Duration duration) pure {
    auto t = duration.split!("seconds", "msecs");    
    return t.seconds + (t.msecs / 1000.0);
}

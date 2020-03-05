// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.common;

import std.string: splitLines;

static string[] ICON_XPM = splitLines(import("data/icon.dxpm"));
enum APPNAME = "DebFind";
enum VERSION = "v0.1.0";
enum MaxPackageNamesForWord = 100; // TODO make this user-configurable

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.common;

import std.string: splitLines;

alias Unit = void[0];
enum unit = Unit.init;

static string[] ICON_XPM = splitLines(import("data/icon.dxpm"));
enum APPNAME = "DebFind";
enum VERSION = "v0.1.0";
enum MAX_DEB_NAMES_FOR_WORD = 100; // TODO make this user-configurable


// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.aboutbox;

import qtrac.debfind.appwindow: AppWindow;

void about(AppWindow parent) {
    import gdk.Pixbuf: Pixbuf;
    import gdkpixbuf.c.types: GdkInterpType;
    import gtk.AboutDialog: AboutDialog;
    import gtk.Version: Version;
    import qtrac.debfind.common: APPNAME, ICON_XPM, VERSION;
    import std.compiler: compiler = name, version_major, version_minor;
    import std.conv: to;
    import std.datetime.systime: Clock;
    import std.format: format;
    import std.system: os;

    auto thisYear = Clock.currTime.year;
    auto year = thisYear == 2020 ? thisYear.to!string
                                 : format("2020-%d", thisYear - 2000);
    auto about = new AboutDialog;
    scope(exit) about.destroy;
    about.setProgramName(APPNAME);
    about.setVersion(VERSION);
    auto icon = new Pixbuf(ICON_XPM).scaleSimple(64, 64,
                                                 GdkInterpType.BILINEAR);
    about.setLogo(icon);
    about.setAuthors(["Mark Summerfield"]);
    about.setComments(
        "An application for searching Debian package files.\n\n" ~ format(
        "Written in D with GtkD %s.%s using %s %s.%s on %s.\n",
        Version.getMajorVersion, Version.getMinorVersion,
        compiler, version_major, version_minor, os));
    about.setCopyright(format(
        "Copyright © %s Mark Summerfield. All rights reserved.", year));
    about.setLicense("Free Open Source Software: GPL-3.0 License");
    about.setWebsite("https://www.qtrac.eu/debfind.html");
    about.setWebsiteLabel("www.qtrac.eu/debfind.html");
    about.setTransientFor(parent);
    about.run;
}

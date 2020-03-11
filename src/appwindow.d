// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.appwindow;

import gtk.ApplicationWindow: ApplicationWindow;

final class AppWindow: ApplicationWindow {
    import gtk.Application: Application;
    import gtk.Widget: Widget;
    import qtrac.debfind.config: config;
    import qtrac.debfind.model: Model;

    private {
        Model model;
    }

    this(Application application) {
        import gdk.Pixbuf: Pixbuf;
        import qtrac.debfind.common: APPNAME, ICON_XPM;

        super(application);
        setTitle(APPNAME);
        setDefaultIcon(new Pixbuf(ICON_XPM));
        makeModel;
        // makeWidgets -- almost all start disables with status "Indexing..."
        // makeLayout
        makeBindings;
        setDefaultSize(config.width, config.height);
        if (config.xyIsValid)
            move(config.x, config.y);
        showAll;
    }

    private void makeModel() {
        import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
        import std.parallelism: task;

        model = Model(MAX_DEB_NAMES_FOR_WORD);
        task(&model.readPackages, &onReady).executeInNewThread;
    }

    void onReady() {
        // TODO enable the UI with status "Read and indexed %,d packages"
        import std.stdio: writefln;
        writefln("read and indexed %,d packages", model.length);
    }

    private void makeBindings() {
        //helpButton.addOnClicked(&onHelp);
        //aboutButton.addOnClicked(&onAbout);
        //quitButton.addOnClicked(
        //    delegate void(ToolButton) { onQuit(null); });
        addOnDelete(
            delegate bool(Event, Widget) { onQuit(null); return false; });
    }

    private void onQuit(Widget) {
        int a;
        int b;
        getSize(a, b);
        config.width = a;
        config.height = b;
        getPosition(a, b);
        config.x = a;
        config.y = b;
        config.save;
        destroy;
    }
}

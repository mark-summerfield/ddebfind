// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.appwindow;

import gtk.ApplicationWindow: ApplicationWindow;

final class AppWindow: ApplicationWindow {
    import gtk.Application: Application;
    import gtk.Statusbar: Statusbar;
    import gtk.Widget: Widget;
    import qtrac.debfind.config: config;
    import qtrac.debfind.model: Model;
    import std.datetime.stopwatch: AutoStart, StopWatch;

    private {
        Model model;
        StopWatch timer;
        Statusbar statusBar;
    }

    this(Application application) {
        import gdk.Pixbuf: Pixbuf;
        import qtrac.debfind.common: APPNAME, ICON_XPM;

        super(application);
        setTitle(APPNAME);
        setDefaultIcon(new Pixbuf(ICON_XPM));
        makeModel;
        makeWidgets;
        makeLayout;
        makeBindings;
        setDefaultSize(config.width, config.height);
        if (config.xyIsValid)
            move(config.x, config.y);
        showAll;
    }

    private void makeModel() {
        import std.parallelism: task;

        timer = StopWatch(AutoStart.yes);
        model = Model();
        task(&model.readPackages, &onReady).executeInNewThread;
    }

    private void makeWidgets() {
        // TODO disable most of the UI (e.g., not Quit or Status)
        statusBar = new Statusbar;
        setStatus("Reading package files…");
    }

    private void makeLayout() {
        import gtk.Box: Box;
        import gtkc.gtktypes: GtkOrientation;

        enum Pad = 1;
        enum: bool {Expand = true, Fill = true,
                    NoExpand = false, NoFill = false}
        auto vbox = new Box(GtkOrientation.VERTICAL, Pad);
        vbox.packEnd(statusBar, NoExpand, Fill, Pad);
        add(vbox);
    }

    private void makeBindings() {
        //helpButton.addOnClicked(&onHelp);
        //aboutButton.addOnClicked(&onAbout);
        //quitButton.addOnClicked(
        //    delegate void(ToolButton) { onQuit(null); });
        addOnDelete(
            delegate bool(Event, Widget) { onQuit(null); return false; });
    }

    private void onReady(bool done, size_t fileCount) {
        import qtrac.debfind.common: decSecs;
        import std.format: format;

        auto secs = decSecs(timer.peek);
        if (!done)
            setStatus(format("Read %,d package files in %0.1f secs. " ~
                             "Indexing…", fileCount, secs));
        else {
            if (!fileCount)
                setStatus(format("Read cached data for %,d packages " ~
                                 "in %0.1f secs.", model.length, secs));
            else
                setStatus(format("Read %,d package files and indexed %,d " ~
                                 "packages in %0.1f secs.", fileCount,
                                  model.length, secs));
            timer.stop;
            // TODO enable the UI
        }
    }

    private void setStatus(const string text) {
        enum ContextId = 1;
        statusBar.removeAll(ContextId);
        statusBar.push(ContextId, text);
    }

    private void onQuit(Widget) {
        model.close;
        saveConfig;
        destroy;
    }

    private void saveConfig() {
        int a;
        int b;
        getSize(a, b);
        config.width = a;
        config.height = b;
        getPosition(a, b);
        config.x = a;
        config.y = b;
        config.save;
    }
}

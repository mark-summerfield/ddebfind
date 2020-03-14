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
        import qtrac.debfind.common: MAX_DEB_NAMES_FOR_WORD;
        import std.parallelism: task;

        timer = StopWatch(AutoStart.yes);
        model = Model(MAX_DEB_NAMES_FOR_WORD);
        task(&model.readPackages, &onReady).executeInNewThread;
    }

    private void makeWidgets() {
        // TODO disable most of the UI (e.g., not Quit or Status)
        statusBar = new Statusbar;
        setStatus("Reading packages…");
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

    private void onReady(bool done) {
        import std.format: format;
        if (!done)
            setStatus(format("Read packages in %s. Indexing…", timer.peek));
        else {
            setStatus(format("Read and indexed %,d packages in %s.",
                             model.length, timer.peek));
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

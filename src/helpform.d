// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.helpform;

import gtk.Window: Window;

final class HelpForm: Window {
    import gdk.Event: Event;
    import gtk.TextView: TextView;
    import gtk.Widget: Widget;
    import qtrac.debfind.common: APPNAME;

    private TextView view;
    private enum SIZE = 400;

    this(Window parent) {
        super("Help — " ~ APPNAME);
        setTransientFor(parent);
        setDefaultSize(SIZE, SIZE);
        makeView;
        populateView;
        makeLayout;
        addOnKeyPress(&onKeyPress);
        showAll;
        view.grabFocus;
    }

    void makeView() {
        import gtk.c.types: GtkWrapMode;

        view = new TextView;
        view.setCursorVisible(false);
        view.setEditable(false);
        view.setWrapMode(GtkWrapMode.WORD);
    }

    void populateView() {
        import gtk.c.types: Justification;
        import gtk.TextIter: TextIter;
        import pango.PgTabArray: PgTabArray;
        import pango.c.types: PANGO_SCALE, PangoTabAlign, PangoWeight,
               PangoUnderline;

        auto tabs = new PgTabArray(1, true);
        tabs.setTab(0, PangoTabAlign.LEFT, SIZE / 5);
        auto buffer = view.getBuffer();
		auto iter = new TextIter();
        buffer.getIterAtOffset(iter, 0);
        buffer.createTag("title",
                         "weight", PangoWeight.BOLD,
                         "size", 14 * PANGO_SCALE,
                         "foreground", "navy",
                         "justification", cast(int)Justification.CENTER);
        buffer.insertWithTagsByName(iter, "DebFind\n\n", "title");
        buffer.insert(iter, import("data/help.txt"));
    }

    void makeLayout() {
        import gtk.ScrolledWindow: PolicyType, ScrolledWindow;
		auto scroll = new ScrolledWindow(PolicyType.AUTOMATIC,
                                         PolicyType.AUTOMATIC);
		scroll.add(view);
        add(scroll);
    }

    private bool onKeyPress(Event event, Widget) {
        import gdk.Keymap: Keymap;
        import std.algorithm: among;

        uint kv;
        event.getKeyval(kv);
        auto name = Keymap.keyvalName(kv);
        if (name.among("q", "Q", "Escape")) {
            destroy;
            return true;
        }
        return false;
    }
}

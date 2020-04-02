// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.appwindow;

import gtk.ApplicationWindow: ApplicationWindow;

final class AppWindow: ApplicationWindow {
    import gtk.Application: Application;
    import gtk.Button: Button;
    import gtk.CheckButton: CheckButton;
    import gtk.ComboBoxText: ComboBoxText;
    import gtk.Entry: Entry;
    import gtk.Label: Label;
    import gtk.ListBox: ListBox;
    import gtk.RadioButton: RadioButton;
    import gtk.Statusbar: Statusbar;
    import gtk.TextView: TextView;
    import gtk.Widget: Widget;
    import qtrac.debfind.config: config;
    import qtrac.debfind.model: Model;
    import std.datetime.stopwatch: AutoStart, StopWatch;

    private {
        Model model;
        StopWatch timer;
        Label descWordsLabel;
        Entry descWordsEntry;
        RadioButton descAllWordsRadioButton;
        RadioButton descAnyWordsRadioButton;
        Label nameWordsLabel;
        Entry nameWordsEntry;
        RadioButton nameAllWordsRadioButton;
        RadioButton nameAnyWordsRadioButton;
        Label sectionLabel;
        ComboBoxText sectionComboBoxText;
        CheckButton librariesCheckButton;
        Button findButton;
        Button helpButton;
        Button aboutButton;
        Button quitButton;
        ListBox debsListBox;
        TextView debTextView;
        Statusbar statusBar;

        enum ANY = "Any"; // For any section: pass to query as ""
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
        import gtkc.gtktypes: Align, StockID;

        descWordsLabel = new Label("Name and D_escription");
        descWordsEntry = new Entry;
        descWordsEntry.setHexpand(true);
        descWordsLabel.setMnemonicWidget(descWordsEntry);
        descAllWordsRadioButton = new RadioButton("All _Words");
        descAnyWordsRadioButton = new RadioButton(
            descAllWordsRadioButton.getGroup(), "Any W_ords");
        nameWordsLabel = new Label("_Name Only");
        nameWordsEntry = new Entry;
        nameWordsEntry.setHexpand(true);
        nameWordsLabel.setMnemonicWidget(nameWordsEntry);
        nameAllWordsRadioButton = new RadioButton("All Wor_ds");
        nameAnyWordsRadioButton = new RadioButton(
            nameAllWordsRadioButton.getGroup(), "Any Word_s");
        sectionLabel = new Label("Se_ction");
        sectionComboBoxText = new ComboBoxText(false);
        sectionComboBoxText.setTitle("Sections");
        sectionComboBoxText.setSensitive(false);
        sectionLabel.setMnemonicWidget(sectionComboBoxText);
        librariesCheckButton = new CheckButton("Include _Libraries");
        findButton = new Button(StockID.FIND);
        findButton.setSensitive(false);
        helpButton = new Button(StockID.HELP);
        aboutButton = new Button(StockID.ABOUT);
        quitButton = new Button(StockID.QUIT);
        debsListBox = new ListBox;
        debsListBox.setHexpand(true);
        debsListBox.setVexpand(true);
        debTextView = new TextView;
        debTextView.setEditable(false);
        debTextView.setHexpand(true);
        debTextView.setVexpand(true);
        statusBar = new Statusbar;
        statusBar.setHexpand(true);
        setStatus("Reading package files…");
    }

    private void makeLayout() {
        import gtk.Grid: Grid;
        import pango.c.types: PANGO_SCALE;
        
        auto metrics = getPangoContext.getMetrics(null, null);
        immutable width = metrics.getApproximateCharWidth /
                          PANGO_SCALE * 15;
        immutable height = (metrics.getAscent + metrics.getDescent) /
                           PANGO_SCALE;
        foreach (button; [findButton, helpButton, aboutButton, quitButton])
            button.setSizeRequest(width, height);

        enum Pad = 4;
        auto grid = new Grid;
        grid.setRowHomogeneous = false;
        grid.setColumnHomogeneous = false;
        grid.setRowSpacing = Pad;
        grid.setColumnSpacing = Pad;
        grid.attach(descWordsLabel, 0, 0, 1, 1);
        grid.attach(descWordsEntry, 1, 0, 2, 1);
        grid.attach(descAllWordsRadioButton, 3, 0, 1, 1);
        grid.attach(descAnyWordsRadioButton, 4, 0, 1, 1);
        grid.attach(quitButton, 5, 0, 1, 1);
        grid.attach(nameWordsLabel, 0, 1, 1, 1);
        grid.attach(nameWordsEntry, 1, 1, 2, 1);
        grid.attach(nameAllWordsRadioButton, 3, 1, 1, 1);
        grid.attach(nameAnyWordsRadioButton, 4, 1, 1, 1);
        grid.attach(aboutButton, 5, 1, 1, 1);
        grid.attach(sectionLabel, 0, 2, 1, 1);
        grid.attach(sectionComboBoxText, 1, 2, 1, 1);
        grid.attach(librariesCheckButton, 2, 2, 2, 1);
        grid.attach(findButton, 4, 2, 1, 1);
        grid.attach(helpButton, 5, 2, 1, 1);
        grid.attach(debsListBox, 0, 5, 3, 1);
        grid.attach(debTextView, 3, 5, 3, 1);
        grid.attach(statusBar, 0, 6, 6, 1);
        add(grid);
    }

    private void makeBindings() {
        //helpButton.addOnClicked(&onHelp);
        //aboutButton.addOnClicked(&onAbout);
        //quitButton.addOnClicked(
        //    delegate void(ToolButton) { onQuit(null); });
        addOnDelete(
            delegate bool(Event, Widget) { onQuit(null); return false; });
    }

    // TODO make F1 work (e.g., onKeyPress or add accel?)

    private void onReady(bool done, size_t fileCount) {
        import qtrac.debfind.common: decSecs;
        import std.algorithm: sort;
        import std.array: array;
        import std.format: format;

        auto secs = decSecs(timer.peek);
        if (!done)
            setStatus(format("Read %,d package files in %0.1f secs. " ~
                             "Indexing…", fileCount, secs));
        else {
            timer.stop;
            if (!fileCount)
                setStatus(format("Read cached data for %,d packages " ~
                                 "in %0.1f secs.", model.length, secs));
            else
                setStatus(format("Read %,d package files and indexed %,d " ~
                                 "packages in %0.1f secs.", fileCount,
                                  model.length, secs));
            sectionComboBoxText.appendText(ANY);
            foreach (section; model.sections.array.sort)
                sectionComboBoxText.appendText(section);
            sectionComboBoxText.setActiveText(ANY);
            sectionComboBoxText.setSensitive(true);
            findButton.setSensitive(true);
        }
    }

    private void setStatus(const string text) {
        enum ContextId = 1;
        statusBar.removeAll(ContextId);
        statusBar.push(ContextId, text);
    }

    private void onQuit(Widget) {
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

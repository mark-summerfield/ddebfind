// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.appwindow;

import gtk.ApplicationWindow: ApplicationWindow;

final class AppWindow: ApplicationWindow {
    import gdk.Event: Event;
    import glib.Timeout: Timeout;
    import gtk.Application: Application;
    import gtk.Button: Button;
    import gtk.CheckButton: CheckButton;
    import gtk.ComboBoxText: ComboBoxText;
    import gtk.Entry: Entry;
    import gtk.Label: Label;
    import gtk.Paned: Paned;
    import gtk.RadioButton: RadioButton;
    import gtk.Statusbar: Statusbar;
    import gtk.TextView: TextView;
    import gtk.Widget: Widget;
    import qtrac.debfind.config: config;
    import qtrac.debfind.model: Model;
    import qtrac.debfind.modelutil: DebNames;
    import qtrac.debfind.view: View;
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
        Button refreshButton;
        Button quitButton;
        Paned splitter;
        View debsView;
        TextView debTextView;
        Statusbar statusBar;
        Timeout timeout;

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
        timeout = new Timeout(200, &fixLayout);
    }

    private void makeModel() {
        import std.parallelism: task;

        timer = StopWatch(AutoStart.yes);
        model = Model();
        task(&model.readPackages, &onReady).executeInNewThread;
    }

    private void makeWidgets() {
        import qtrac.debfind.common: APPNAME;
        import gtkc.gtktypes: Align, GtkOrientation, StockID;

        descWordsLabel = new Label("Name and D_escription");
        descWordsEntry = new Entry;
        descWordsEntry.setHexpand(true);
        descWordsEntry.setTooltipMarkup(
            "The word(s) to find in the package's description or name");
        descWordsLabel.setMnemonicWidget(descWordsEntry);
        descAllWordsRadioButton = new RadioButton("All _Words");
        descAllWordsRadioButton.setTooltipMarkup(
            "Match all Name and Description words");
        descAnyWordsRadioButton = new RadioButton(
            descAllWordsRadioButton.getGroup(), "Any W_ords");
        descAnyWordsRadioButton.setTooltipMarkup(
            "Match any of the Name and Description words");
        nameWordsLabel = new Label("_Name Only");
        nameWordsEntry = new Entry;
        nameWordsEntry.setHexpand(true);
        nameWordsEntry.setTooltipMarkup(
            "The word(s) to find in the package's name");
        nameWordsLabel.setMnemonicWidget(nameWordsEntry);
        nameAllWordsRadioButton = new RadioButton("All Wor_ds");
        nameAllWordsRadioButton.setTooltipMarkup("Match all Name words");
        nameAnyWordsRadioButton = new RadioButton(
            nameAllWordsRadioButton.getGroup(), "Any Word_s");
        nameAnyWordsRadioButton.setTooltipMarkup(
            "Match any of the Name words");
        sectionLabel = new Label("Se_ction");
        sectionComboBoxText = new ComboBoxText(false);
        sectionComboBoxText.setTooltipMarkup(
            "The section to restrict the search to");
        sectionComboBoxText.setTitle("Sections");
        sectionComboBoxText.setSensitive(false);
        sectionLabel.setMnemonicWidget(sectionComboBoxText);
        librariesCheckButton = new CheckButton("Include _Libraries");
        librariesCheckButton.setTooltipMarkup(
            "Whether to include libraries in the search");
        findButton = new Button(StockID.FIND);
        findButton.setSensitive(false);
        findButton.setTooltipMarkup(
            "Find matching packages <b>Alt+F</b> or <b>F3</b>");
        helpButton = new Button(StockID.HELP);
        helpButton.setTooltipMarkup(
            "Show online help <b>Alt+H</b> or <b>F1</b>");
        aboutButton = new Button(StockID.ABOUT);
        aboutButton.setTooltipMarkup(
            "Show information about " ~ APPNAME ~ " <b>Alt+A</b>");
        refreshButton = new Button(StockID.REFRESH);
        refreshButton.setTooltipMarkup(
            "Clear the cache and re-read and re-index packages " ~
            "<b>Alt+R</b> or <b>F5</b>");
        quitButton = new Button(StockID.QUIT);
        quitButton.setTooltipMarkup(
            "Terminate the application <b>Alt+Q</b>");
        splitter = new Paned(GtkOrientation.HORIZONTAL);
        splitter.setWideHandle(true);
        debsView = new View;
        debsView.setHexpand(true);
        debsView.setVexpand(true);
        debsView.setTooltipMarkup(
            "The list of matching Debian packages (if any)");
        debTextView = new TextView;
        debTextView.setEditable(false);
        debTextView.setHexpand(true);
        debTextView.setVexpand(true);
        debTextView.setTooltipMarkup(
            "The details of the selected Debian package (if any)");
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
        foreach (button; [findButton, helpButton, aboutButton,
                          refreshButton, quitButton])
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
        grid.attach(refreshButton, 5, 0, 1, 1);
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
        splitter.pack1(debsView, false, true);
        splitter.pack2(debTextView, true, true);
        grid.attach(splitter, 0, 3, 6, 1);
        grid.attach(statusBar, 0, 4, 5, 1);
        grid.attach(quitButton, 5, 4, 1, 1);
        add(grid);
    }

    private void makeBindings() {
        aboutButton.addOnClicked(&onAbout);
        helpButton.addOnClicked(&onHelp);
        findButton.addOnClicked(&onFind);
        refreshButton.addOnClicked(&onRefresh);
        quitButton.addOnClicked(delegate void(Button) { onQuit(null); });
        addOnDelete(
            delegate bool(Event, Widget) { onQuit(null); return false; });
        addOnKeyPress(&onKeyPress);
    }

    private bool onKeyPress(Event event, Widget) {
        import gdk.Keymap: Keymap;

        uint kv;
        event.getKeyval(kv);
        immutable key = Keymap.keyvalName(kv);
        if (key == "F1") {
            onHelp(null);
            return true;
        }
        if (key == "F3") {
            onFind(null);
            return true;
        }
        if (key == "F5") {
            onRefresh(null);
            return true;
        }
        return false;
    }

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
            refreshButton.setSensitive(true);
        }
    }

    private bool fixLayout() {
        splitter.setPosition(splitter.getAllocatedWidth / 2);
        return false;
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

    private void onAbout(Button) {
        import qtrac.debfind.aboutbox: about;
        about(this);
    }

    private void onHelp(Button) {
        import qtrac.debfind.helpform: HelpForm;
        new HelpForm(this);
    }

    private void onRefresh(Button) {
        import std.parallelism: task;

        findButton.setSensitive(false);
        refreshButton.setSensitive(false);
        sectionComboBoxText.setSensitive(false);
        setStatus("Refreshing…");
        timer = StopWatch(AutoStart.yes);
        task(&model.refresh, &onReady).executeInNewThread;
    }

    private void onFind(Button) {
        clearNames;
        auto names = findMatchingNames();
        if (names.empty) {
            setStatus("No matching packages found.");
        } else {
            if (names.length == 1)
                setStatus("One matching package found.");
            else {
                import std.format: format;
                setStatus(format("%,d matching packages found.",
                                 names.length));
            }
            populateNames(names);
        }
    }

    private void clearNames() {
        import gtk.TextIter: TextIter;

        auto buffer = debTextView.getBuffer;
        TextIter start;
        TextIter end;
        buffer.getBounds(start, end);
        buffer.delete_(start, end);
        debsView.clear;
    }

    private DebNames findMatchingNames() {
        import qtrac.debfind.query: Query;

        auto query = Query();
        immutable section = sectionComboBoxText.getActiveText;
        if (section !is null && section != ANY)
            query.section = section;
        immutable descriptionWords = descWordsEntry.getText;
        if (descriptionWords !is null)
            query.descriptionWords = descriptionWords;
        query.matchAnyDescriptionWord = descAnyWordsRadioButton.getActive;
        immutable nameWords = nameWordsEntry.getText;
        if (nameWords !is null)
            query.descriptionWords = nameWords;
        query.matchAnyNameWord = nameAnyWordsRadioButton.getActive;
        query.includeLibraries = librariesCheckButton.getActive;
        return model.query(query);
    }

    private void populateNames(DebNames names) {
        auto namesAndDescriptions = model.namesAndDescriptions(names);
        debsView.populate(namesAndDescriptions);
        // TODO:
        //      populate debs view
        //      select first one
        //      populate debTextView
        import std.stdio: writeln; writeln("populateNames"); // TODO
    }
}

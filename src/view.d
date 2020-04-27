// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.view;

import gtk.ScrolledWindow: ScrolledWindow;
import gtk.TreeView: TreeView;

class View : ScrolledWindow {
    import qtrac.debfind.modelutil: NameAndDescription;

    InnerView innerView;

    this() {
        super();
        innerView = new InnerView;
        addWithViewport(innerView);
    }

    void clear() {
        innerView.viewData.clear;
    }

    void populate(NameAndDescription[] namesAndDescriptions) {
        innerView.viewData.populate(namesAndDescriptions);
    }
}

class InnerView : TreeView {
    import gtk.CellRendererText: CellRendererText;
    import gtk.TreeViewColumn: TreeViewColumn;
    import qtrac.debfind.modelutil: NameAndDescription;
    import qtrac.debfind.viewdata: ViewData;

    ViewData viewData;
    TreeViewColumn nameColumn;
    TreeViewColumn descriptionColumn;

    this() {
        super();
        setActivateOnSingleClick(true);
        viewData = new ViewData;
        setModel(viewData);
        auto renderer = new CellRendererText;
        nameColumn = new TreeViewColumn("Name", renderer, "text", 0);
        nameColumn.setResizable(true);
        appendColumn(nameColumn);
        renderer = new CellRendererText;
        descriptionColumn = new TreeViewColumn("Description", renderer,
                                               "text", 1);
        descriptionColumn.setResizable(true);
        appendColumn(descriptionColumn);
    }

    void clear() {
        viewData.clear;
    }

    void populate(NameAndDescription[] namesAndDescriptions) {
        viewData.populate(namesAndDescriptions);
    }
}

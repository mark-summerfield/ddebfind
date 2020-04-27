// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.view;

import gtk.TreeView: TreeView;

class View : TreeView {
    import gtk.CellRendererText: CellRendererText;
    import gtk.TreeViewColumn: TreeViewColumn;
    import qtrac.debfind.modelutil: NameAndDescription;
    import qtrac.debfind.viewdata: ViewData;

    ViewData viewData;
    TreeViewColumn nameColumn;
    TreeViewColumn descriptionColumn;

    this() {
        super();
        viewData = new ViewData;
        setModel(viewData);
        auto renderer = new CellRendererText;
        nameColumn = new TreeViewColumn("Name", renderer, "text", 0);
        appendColumn(nameColumn);
        renderer = new CellRendererText;
        descriptionColumn = new TreeViewColumn("Description", renderer,
                                               "text", 1);
        appendColumn(descriptionColumn);
    }

    void clear() {
        viewData.clear;
    }

    void populate(NameAndDescription[] namesAndDescriptions) {
        viewData.populate(namesAndDescriptions);
    }
}

// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.viewdata;

import gtk.ListStore: ListStore;

class ViewData : ListStore {
    import qtrac.debfind.modelutil: NameAndDescription;

    this() {
        import gobject.c.types: GType;
        super([GType.STRING, GType.STRING]);
    }

    void populate(NameAndDescription[] namesAndDescriptions) {
        import gtk.TreeIter: TreeIter;

        clear;
        TreeIter iter;
        foreach (nameAndDescription; namesAndDescriptions) {
            append(iter);
            setValue(iter, 0, nameAndDescription.name);
            setValue(iter, 1, nameAndDescription.description);
        }
    }
}

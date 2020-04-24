// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.namestore;

import gtk.ListStore: ListStore;

class NameStore : ListStore {
    import qtrac.debfind.modelutil: DebNames;

    this(DebNames names) {
        import gobject.c.types: GType;
        import gtk.TreeIter: TreeIter;

        super([GType.STRING]);

        TreeIter iter;
        foreach (name; names) {
            append(iter);
            setValue(iter, 0, name);
        }
    }
}

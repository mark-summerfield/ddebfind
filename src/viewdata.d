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
        foreach (i, nameAndDescription; namesAndDescriptions) {
            append(iter);
            setValue(iter, 0, nameAndDescription.name);
            setValue(iter, 1,
                     maybeTruncate(nameAndDescription.description));
        }
    }
}

string maybeTruncate(string text, size_t limit=80) {
    import std.string: indexOf;

    if (text.length < limit) {
        auto i = text.indexOf('\n');
        if (i > -1)
            return text[0 .. i];
        return text;
    }
    size_t i;
    size_t j;
    foreach (c; text) {
        if (j >= limit - 1)
            break;
        if (c == '\n') {
            i = j;
            break;
        }
        if (c == ' ')
            i = j;
        j++;
    }
    if (i > 0)
        text = text[0 .. i];
    else if (j > 0)
        text = text[0 .. j];
    else
        return text; // Shouldn't happen
    return text ~ "…";
}

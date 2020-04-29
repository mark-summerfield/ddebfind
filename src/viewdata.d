// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.viewdata;

enum UseListStore = false;

static if(UseListStore) {

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
            setValue(iter, 1,
                     maybeTruncate(nameAndDescription.description));
        }
    }
}
}
else {
import gobject.ObjectG: ObjectG;
import gtk.TreeModelIF: TreeModelIF;

// Record and ViewData adapted from the GtkD CustomList example

struct Record {
    // Our data
    string name;
    string description;
    // List's data
    uint pos;
}

class ViewData : ObjectG, TreeModelIF {
    import gobject.ObjectG: GObject;
    import gobject.Value: Value;
    import gobject.c.types: GType;
    import gtk.TreeIter: TreeIter;
    import gtk.TreeModel: GtkTreeModel;
    import gtk.TreeModelT; // Get the lot since the mixins use so many
    import gtk.TreePath: TreePath;
    import gtkd.Implement: ImplementInterface, ImplementInterfaceImpl;
    import qtrac.debfind.modelutil: NameAndDescription;
    import std.algorithm: startsWith;

    enum ColumnCount = 2;
    enum ListColumn { Name, Description, Record }

	uint rowCount;
	int stamp;
    Record*[] rows;

	mixin ImplementInterface!(GObject, GtkTreeModelIface);
	mixin TreeModelT!(GtkTreeModel);

	public this() {
        super(getType(), null);
        import glib.RandG: RandG;
		stamp = RandG.randomInt();
    }

    void clear() {
        rowCount = 0;
        rows.length = 0;
    }

	override GtkTreeModelFlags getFlags() {
		return (GtkTreeModelFlags.LIST_ONLY |
                GtkTreeModelFlags.ITERS_PERSIST);
	}

	override int getNColumns() { return ColumnCount; }

	override GType getColumnType(int index) {
        if (index == 0 || index == 1)
            return GType.STRING;
        return GType.INVALID;
	}

	override int getIter(TreeIter iter, TreePath path) {
		auto indices = path.getIndices();
		immutable depth = path.getDepth();

		if (depth != 1) // Lists have no children
			return false;
		auto n = indices[0]; // the n-th top level row
		if (n >= rowCount || n < 0)
			return false;
		Record* record = rows[n];
		if (record is null)
			throw new Exception("Non-existent record requested");
		if (record.pos != n)
			throw new Exception("record.pos != TreePath.getIndices()[0]");
		// We simply store a pointer to our custom record in the iter 
		iter.stamp = stamp;
		iter.userData = record;
		return true;
	}

	override TreePath getPath(TreeIter iter) {
		if (iter is null || iter.userData is null || iter.stamp != stamp)
			return null;
		Record* record = cast(Record*) iter.userData;
		return new TreePath(record.pos);
	}

	override Value getValue(TreeIter iter, int column, Value value=null) {
		if (value is null)
			value = new Value();
		if (iter is null || column >= ColumnCount || iter.stamp != stamp)
			return null;
		value.init(GType.STRING); // Our two columns are always strings
		Record* record = cast(Record*) iter.userData;
		if (record is null || record.pos >= rowCount)
			return null;
		switch(column) {
			case ListColumn.Name:
				value.setString(record.name);
				break;
			case ListColumn.Description:
				value.setString(record.description);
				break;
			case ListColumn.Record:
				value.setPointer(record);
				break;
			default:
				break;
		}
		return value;
	}

	override bool iterNext(TreeIter iter) {
		if (iter is null || iter.userData is null || iter.stamp != stamp)
			return false;
		Record* record = cast(Record*) iter.userData;
		// Is this the last record in the list? 
		if ((record.pos + 1) >= rowCount)
			return false;
		Record* nextRecord = rows[(record.pos + 1)];
		if (nextRecord is null || nextRecord.pos != record.pos + 1)
			throw new Exception("Invalid next record");
		iter.stamp = stamp;
		iter.userData = nextRecord;
		return true;
	}

	override bool iterChildren(out TreeIter iter, TreeIter parent) {
		if (parent !is null) // List nodes have no children
			return false;
		if (rowCount == 0) // No rows => no first row 
			return false;
		// Set iter to first item in list 
		iter = new TreeIter();
		iter.stamp = stamp;
		iter.userData = rows[0];
		return true;
	}

	override bool iterHasChild(TreeIter iter) { return false; }

	override int iterNChildren(TreeIter iter) {
		// special case: if iter == NULL, return number of top-level rows
		if (iter is null)
			return rowCount;
		return 0; // otherwise, this is easy again for a list
	}

	override bool iterNthChild(out TreeIter iter, TreeIter parent, int n) {
		if (parent !is null) // a list has only top-level rows
			return false;
		if (n >= rowCount)
			return false;
		Record* record = rows[n];
		if (record == null || record.pos != n)
			throw new Exception("Invalid record");
		iter = new TreeIter();
		iter.stamp = stamp;
		iter.userData = record;
		return true;
	}

	override bool iterParent(out TreeIter iter, TreeIter child) {
		return false;
	}

	void appendRecord(string name, string description)
	{
		if (name is null)
			return;
		uint pos = rowCount++;
        Record* record = new Record;
        record.name = name;
        record.description = description;
		rows ~= record;
		record.pos = pos;
		/* inform the tree view and other interested objects
		 *  (e.g. tree row references) that we have inserted
		 *  a new row, and where it was inserted */
		auto path = new TreePath(pos);
		auto iter = new TreeIter();
		getIter(iter, path);
		rowInserted(path, iter);
	}

    void populate(NameAndDescription[] namesAndDescriptions) {
        clear;
        foreach (nameAndDescription; namesAndDescriptions)
            appendRecord(nameAndDescription.name,
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
    foreach (c; text) { // Safe to use chars 'cos we only chop on SPC | NL
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


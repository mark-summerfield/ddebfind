// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.kind;

enum Kind {Any, ConsoleApp, GuiApp, Library, Font, Data, Documentation,
           Unknown}

string toString(Kind kind) {
    final switch (kind) {
        case Kind.Any: return "A";
        case Kind.ConsoleApp: return "C";
        case Kind.GuiApp: return "G";
        case Kind.Library: return "L";
        case Kind.Font: return "F";
        case Kind.Data: return "D";
        case Kind.Documentation: return "M";
        case Kind.Unknown: return "U";
    }
}

Kind fromString(string kind) {
    switch (kind) {
        case "A": return Kind.Any;
        case "C": return Kind.ConsoleApp;
        case "G": return Kind.GuiApp;
        case "L": return Kind.Library;
        case "F": return Kind.Font;
        case "D": return Kind.Data;
        case "M": return Kind.Documentation;
        default: return Kind.Unknown;
    }
}

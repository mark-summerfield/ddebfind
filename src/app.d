// Copyright © 2020 Mark Summerfield. All rights reserved.
module qtrac.debfind.app;

int main(string[] args) {
    import gio.Application: GioApplication = Application;
    import gtk.Application: Application;
    import gtk.ApplicationWindow: GApplicationFlags;

    auto application = new Application("eu.qtrac.debfind",
                                       GApplicationFlags.FLAGS_NONE);
    application.addOnActivate(delegate void(GioApplication) {
        import qtrac.debfind.appwindow: AppWindow;
        new AppWindow(application);
        });
    return application.run(args);
}

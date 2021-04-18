/*
 * Copyright (c) 2011-2019 elementary, Inc. (https://elementary.io)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 */

public class Session.Indicator : Wingpanel.Indicator {
    private const string ICON_NAME = "system-shutdown-symbolic";
   // private const string KEYBINDING_SCHEMA = "org.gnome.settings-daemon.plugins.media-keys";

    //private LockInterface lock_interface;
    private SessionInterface session_interface;
    private SystemInterface system_interface;

    private Wingpanel.IndicatorManager.ServerType server_type;
    private Wingpanel.Widgets.OverlayIcon indicator_icon;

    //private Gtk.ModelButton lock_screen;
    private Gtk.ModelButton reboot;
    private Gtk.ModelButton shutdown;
    private Gtk.ModelButton log_out;

    private Session.Services.UserManager manager;
    private Widgets.EndSessionDialog? current_dialog = null;

    private Gtk.Grid? main_grid;

    //private static GLib.Settings? keybinding_settings;

    public Indicator (Wingpanel.IndicatorManager.ServerType server_type) {
        Object (code_name: Wingpanel.Indicator.SESSION);
        this.server_type = server_type;
        this.visible = true;

        EndSessionDialogServer.init ();
        EndSessionDialogServer.get_default ().show_dialog.connect ((type) => show_dialog ((Widgets.EndSessionDialogType)type));
    }

    /*static construct {
        if (SettingsSchemaSource.get_default ().lookup (KEYBINDING_SCHEMA, true) != null) {
            keybinding_settings = new GLib.Settings (KEYBINDING_SCHEMA);
        }
    }*/

    public override Gtk.Widget get_display_widget () {
        if (indicator_icon == null) {
            indicator_icon = new Wingpanel.Widgets.OverlayIcon (ICON_NAME);
            indicator_icon.button_press_event.connect ((e) => {
                if (e.button == Gdk.BUTTON_MIDDLE) {
                    if (session_interface == null) {
                        init_interfaces.begin ((obj, res) => {
                            init_interfaces.end (res);
                            //show_shutdown_dialog ();
                        });
                    } else {
                        //show_shutdown_dialog ();
                    }

                    return Gdk.EVENT_STOP;
                }

                return Gdk.EVENT_PROPAGATE;
            });
        }

        return indicator_icon;
    }

    public override Gtk.Widget? get_widget () {
        if (main_grid == null) {
            init_interfaces.begin ();

            main_grid = new Gtk.Grid ();
            main_grid.set_orientation (Gtk.Orientation.VERTICAL);

            var user_settings = new Gtk.ModelButton ();
            user_settings.text = _("User Accounts Settings…");

            //var log_out_grid = new Granite.AccelLabel (_("Log Out…"));

            log_out = new Gtk.ModelButton () {
                sensitive = false,
                text = _("Log Out")
            };

            /*log_out.get_child ().destroy ();
            log_out.add (log_out_grid);*/

            //var lock_screen_grid = new Granite.AccelLabel (_("Lock"));

            /*lock_screen = new Gtk.ModelButton () {
                sensitive = false
            };

            lock_screen.get_child ().destroy ();
            lock_screen.add (lock_screen_grid);*/

            reboot = new Gtk.ModelButton () {
                sensitive = false,
                text = _("Reboot")
            };
            
            shutdown = new Gtk.ModelButton () {
                hexpand = true,
                text = _("Shut Down")
            };

            if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
                var users_separator = new Wingpanel.Widgets.Separator ();
                manager = new Session.Services.UserManager (users_separator);

                var scrolled_box = new Gtk.ScrolledWindow (null, null);
                scrolled_box.hexpand = true;
                scrolled_box.hscrollbar_policy = Gtk.PolicyType.NEVER;
                scrolled_box.max_content_height = 300;
                scrolled_box.propagate_natural_height = true;
                scrolled_box.add (manager.user_grid);

                main_grid.add (scrolled_box);
                main_grid.add (user_settings);
                main_grid.add (users_separator);
                //main_grid.add (lock_screen);
                main_grid.add (log_out);
                //main_grid.add (new Wingpanel.Widgets.Separator ());
            }

            main_grid.add (reboot);
            main_grid.add (shutdown);

           /* if (keybinding_settings != null) {
                // This key type has changed in recent versions of GNOME Settings Daemon
                unowned VariantType key_type = keybinding_settings.get_value ("logout").get_type ();
                if (key_type.equal (VariantType.STRING)) {
                    log_out_grid.accel_string = keybinding_settings.get_string ("logout");
                    lock_screen_grid.accel_string = keybinding_settings.get_string ("screensaver");

                    keybinding_settings.changed["logout"].connect (() => {
                        log_out_grid.accel_string = keybinding_settings.get_string ("logout");
                    });

                    keybinding_settings.changed["screensaver"].connect (() => {
                        lock_screen_grid.accel_string = keybinding_settings.get_string ("screensaver");
                    });
                } else if (key_type.equal (VariantType.STRING_ARRAY)) {
                    log_out_grid.accel_string = keybinding_settings.get_strv ("logout")[0];
                    lock_screen_grid.accel_string = keybinding_settings.get_strv ("screensaver")[0];

                    keybinding_settings.changed["logout"].connect (() => {
                        log_out_grid.accel_string = keybinding_settings.get_strv ("logout")[0];
                    });

                    keybinding_settings.changed["screensaver"].connect (() => {
                        lock_screen_grid.accel_string = keybinding_settings.get_strv ("screensaver")[0];
                    });
                }
            }*/

            manager.close.connect (() => close ());

            user_settings.clicked.connect (() => {
                close ();

                try {
                    AppInfo.launch_default_for_uri ("settings://accounts", null);
                } catch (Error e) {
                    warning ("Failed to open user accounts settings: %s", e.message);
                }
            });

            shutdown.clicked.connect (() => {
                //show_shutdown_dialog ();
            });

            reboot.clicked.connect (() => {
                /*close ();

                try {
                    system_interface.suspend (true);
                } catch (GLib.Error e) {
                    warning ("Unable to suspend: %s", e.message);
                }*/
            });

            log_out.clicked.connect (() => {
               /* session_interface.logout.begin (0, (obj, res) => {
                    try {
                        session_interface.logout.end (res);
                    } catch (Error e) {
                        if (!(e is GLib.IOError.CANCELLED)) {
                            warning ("Unable to open logout dialog: %s", e.message);
                        }
                    }
                });*/
            });

            /*lock_screen.clicked.connect (() => {
                close ();

                try {
                    lock_interface.lock ();
                } catch (GLib.Error e) {
                    warning ("Unable to lock: %s", e.message);
                }
            });*/
        }

        return main_grid;
    }

    /*private void show_shutdown_dialog () {
        close ();

        if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
            // Ask gnome-session to "reboot" which throws the EndSessionDialog
            // Our "reboot" dialog also has a shutdown button to give the choice between reboot/shutdown
            session_interface.reboot.begin ((obj, res) => {
                try {
                    session_interface.reboot.end (res);
                } catch (Error e) {
                    if (!(e is GLib.IOError.CANCELLED)) {
                        critical ("Unable to open shutdown dialog: %s", e.message);
                    }
                }
            });
        } else {
            show_dialog (Widgets.EndSessionDialogType.RESTART);
        }
    }*/

    private async void init_interfaces () {
        try {
            system_interface = yield Bus.get_proxy (BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
            reboot.sensitive = true;
        } catch (IOError e) {
            critical ("Unable to connect to the login interface: %s", e.message);
            reboot.set_sensitive (false);
        }

        if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
            /*try {
                lock_interface = yield Bus.get_proxy (BusType.SESSION, "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver");
                lock_screen.sensitive = true;
            } catch (IOError e) {
                warning ("Unable to connect to lock interface: %s", e.message);
            }*/

            try {
                session_interface = yield Bus.get_proxy (BusType.SESSION, "org.gnome.SessionManager", "/org/gnome/SessionManager");
                shutdown.sensitive = true;
                log_out.sensitive = true;
            } catch (IOError e) {
                critical ("Unable to connect to GNOME session interface: %s", e.message);
            }
        }
    }

    public override void opened () {
        if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
            manager.update_all ();
        }

        main_grid.show_all ();
    }

    public override void closed () {}

    private void show_dialog (Widgets.EndSessionDialogType type) {
        close ();

        if (current_dialog != null) {
            if (current_dialog.dialog_type != type) {
                current_dialog.destroy ();
            } else {
                return;
            }
        }

        unowned EndSessionDialogServer server = EndSessionDialogServer.get_default ();

        current_dialog = new Widgets.EndSessionDialog (type);
        current_dialog.destroy.connect (() => {
            server.closed ();
            current_dialog = null;
        });

        current_dialog.cancelled.connect (() => {
            server.canceled ();
        });

        current_dialog.logout.connect (() => {
            server.confirmed_logout ();
        });

        current_dialog.shutdown.connect (() => {
            if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
                server.confirmed_shutdown ();
            } else {
                try {
                    system_interface.power_off (false);
                } catch (Error e) {
                    warning ("Unable to shutdown: %s", e.message);
                }
            }
        });

        current_dialog.reboot.connect (() => {
            if (server_type == Wingpanel.IndicatorManager.ServerType.SESSION) {
                server.confirmed_reboot ();
            } else {
                try {
                    system_interface.reboot (false);
                } catch (Error e) {
                    warning ("Unable to reboot: %s", e.message);
                }
            }
        });

        current_dialog.set_transient_for (indicator_icon.get_toplevel () as Gtk.Window);
        current_dialog.show_all ();
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    debug ("Activating Session Indicator");
    var indicator = new Session.Indicator (server_type);

    return indicator;
}

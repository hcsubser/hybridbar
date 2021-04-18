/*
 * Copyright (c) 2011-2020 elementary, Inc. (https://elementary.io)
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

public enum UserState {
    ACTIVE,
    ONLINE,
    OFFLINE;

    public static UserState to_enum (string state) {
        switch (state) {
            case "active":
                return UserState.ACTIVE;
            case "online":
                return UserState.ONLINE;
        }

        return UserState.OFFLINE;
    }
}

public class Session.Services.UserManager : Object {
    public signal void close ();

    public Session.Widgets.UserListBox user_grid { get; private set; }
    public Wingpanel.Widgets.Separator users_separator { get; construct; }

    private const uint GUEST_USER_UID = 999;
    private const uint NOBODY_USER_UID = 65534;
    private const uint RESERVED_UID_RANGE_END = 1000;

    private const string DM_DBUS_ID = "org.freedesktop.DisplayManager";
    private const string LOGIN_IFACE = "org.freedesktop.login1";
    private const string LOGIN_PATH = "/org/freedesktop/login1";

    private Act.UserManager manager;
    private Gee.HashMap<uint, Widgets.Userbox>? user_boxes;
    private SeatInterface? dm_proxy = null;

    private static SystemInterface? login_proxy;

    static construct {
        init_login_proxy.begin ();
    }

    private static async void init_login_proxy () {
        try {
            login_proxy = yield Bus.get_proxy (BusType.SYSTEM, LOGIN_IFACE, LOGIN_PATH, DBusProxyFlags.NONE);
        } catch (IOError e) {
            critical ("Failed to create login1 dbus proxy: %s", e.message);
        }
    }

    public static async UserState get_user_state (uint32 uuid) {
        if (login_proxy == null) {
            return UserState.OFFLINE;
        }

        try {
            UserInfo[] users = login_proxy.list_users ();
            if (users == null) {
                return UserState.OFFLINE;
            }

            foreach (UserInfo user in users) {
                if (user.uid == uuid) {
                    if (user.user_object == null) {
                        return UserState.OFFLINE;
                    }
                    UserInterface? user_interface = yield Bus.get_proxy (BusType.SYSTEM, LOGIN_IFACE, user.user_object, DBusProxyFlags.NONE);
                    if (user_interface == null) {
                        return UserState.OFFLINE;
                    }
                    return UserState.to_enum (user_interface.state);
                }
            }

        } catch (GLib.Error e) {
            critical ("Failed to get user state: %s", e.message);
        }

        return UserState.OFFLINE;
    }

    public static async UserState get_guest_state () {
        if (login_proxy == null) {
            return UserState.OFFLINE;
        }

        try {
            UserInfo[] users = login_proxy.list_users ();
            foreach (UserInfo user in users) {
                var state = yield get_user_state (user.uid);
                if (user.user_name.has_prefix ("guest-")
                    && state == UserState.ACTIVE) {
                    return UserState.ACTIVE;
                }
            }
        } catch (GLib.Error e) {
            critical ("Failed to get Guest state: %s", e.message);
        }

        return UserState.OFFLINE;
    }

    public UserManager (Wingpanel.Widgets.Separator users_separator) {
        Object (users_separator: users_separator);
    }

    construct {
        user_boxes = new Gee.HashMap<uint, Widgets.Userbox> ();

        users_separator.no_show_all = true;
        users_separator.visible = false;

        user_grid = new Session.Widgets.UserListBox ();
        user_grid.close.connect (() => close ());

        manager = Act.UserManager.get_default ();
        init_users ();

        manager.user_added.connect (add_user);
        manager.user_removed.connect (remove_user);
        manager.user_is_logged_in_changed.connect (update_user);

        manager.notify["is-loaded"].connect (() => {
            init_users ();
        });

        var seat_path = Environment.get_variable ("XDG_SEAT_PATH");
        var session_path = Environment.get_variable ("XDG_SESSION_PATH");

        if (seat_path != null) {
            try {
                dm_proxy = Bus.get_proxy_sync (BusType.SYSTEM, DM_DBUS_ID, seat_path, DBusProxyFlags.NONE);
                if (dm_proxy.has_guest_account) {
                    add_guest ();
                }
            } catch (IOError e) {
                critical ("UserManager error: %s", e.message);
            }
        }

        if (dm_proxy != null) {
            user_grid.switch_to_guest.connect (() => {
                try {
                    dm_proxy.switch_to_guest ("");
                } catch (Error e) {
                    warning ("Error switching to guest account: %s", e.message);
                }
            });

            user_grid.switch_to_user.connect ((username) => {
                try {
                    dm_proxy.switch_to_user (username, session_path);
                } catch (Error e) {
                    warning ("Error switching to user '%s': %s", username, e.message);
                }
            });
        }
    }

    private void init_users () {
        if (!manager.is_loaded) {
            return;
        }

        foreach (Act.User user in manager.list_users ()) {
            add_user (user);
        }
    }

    private void add_user (Act.User? user) {
        // Don't add any of the system reserved users
        var uid = user.get_uid ();
        if (uid < RESERVED_UID_RANGE_END || uid == NOBODY_USER_UID || user_boxes.has_key (uid)) {
            return;
        }

        user_boxes[uid] = new Session.Widgets.Userbox (user);
        user_grid.add (user_boxes[uid]);

        users_separator.visible = true;
    }

    private void remove_user (Act.User user) {
        var uid = user.get_uid ();
        var userbox = user_boxes[uid];
        if (userbox == null) {
            return;
        }

        user_boxes.unset (uid);
        user_grid.remove (userbox);
    }

    private void update_user (Act.User user) {
        var userbox = user_boxes[user.get_uid ()];
        if (userbox == null) {
            return;
        }

        userbox.update_state.begin ();
    }

    public void update_all () {
        foreach (var userbox in user_boxes.values) {
            userbox.update_state.begin ();
        }
    }

    private void add_guest () {
        if (user_boxes[GUEST_USER_UID] != null) {
            return;
        }

        user_boxes[GUEST_USER_UID] = new Session.Widgets.Userbox.guest ();
        user_boxes[GUEST_USER_UID].show ();

        user_grid.add (user_boxes[GUEST_USER_UID]);

        users_separator.visible = true;
    }
}

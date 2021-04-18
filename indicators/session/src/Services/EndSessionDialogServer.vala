/*
 * Copyright (c) 2011-2018 elementary LLC. (http://launchpad.net/wingpanel)
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

[DBus (name = "io.elementary.wingpanel.session.EndSessionDialog")]
public class Session.EndSessionDialogServer : Object {
    private static EndSessionDialogServer? instance;

    [DBus (visible = false)]
    public static void init () {
        Bus.own_name (BusType.SESSION, "io.elementary.wingpanel.session.EndSessionDialog", BusNameOwnerFlags.NONE,
            (connection) => {
                try {
                    connection.register_object ("/io/elementary/wingpanel/session/EndSessionDialog", get_default ());
                } catch (Error e) {
                    warning (e.message);
                }
            },
            () => {},
            () => warning ("Could not acquire name"));
    }

    public static unowned EndSessionDialogServer get_default () {
        if (instance == null) {
            instance = new EndSessionDialogServer ();
        }

        return instance;
    }

    [DBus (visible = false)]
    public signal void show_dialog (uint type);

    public signal void confirmed_logout ();
    public signal void confirmed_reboot ();
    public signal void confirmed_shutdown ();
    public signal void canceled ();
    public signal void closed ();

    private EndSessionDialogServer () {

    }

    public void open (uint type, uint timestamp, uint open_length, ObjectPath[] inhibiters) throws Error {
        if (type > (int)Widgets.EndSessionDialogType.RESTART) {
            throw new DBusError.NOT_SUPPORTED ("Hibernate, suspend and hybrid sleep are not supported actions yet");
        }

        show_dialog (type);
    }
}

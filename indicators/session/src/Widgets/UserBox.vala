/*
 * Copyright (c) 2011-2017 elementary LLC. (http://launchpad.net/wingpanel)
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

public class Session.Widgets.Userbox : Gtk.ListBoxRow {
    private const int ICON_SIZE = 48;

    public Act.User? user { get; construct; default = null; }
    public string fullname { get; construct set; }
    public UserState state { get; private set; }

    public bool is_guest {
        get {
            return user == null;
        }
    }

    private Hdy.Avatar avatar;
    private Gtk.Label fullname_label;
    private Gtk.Label status_label;

    public Userbox (Act.User user) {
        Object (user: user);
    }

    public Userbox.guest () {
        Object (fullname: _("Guest"));
    }

    construct {
        fullname_label = new Gtk.Label ("<b>%s</b>".printf (fullname));
        fullname_label.use_markup = true;
        fullname_label.valign = Gtk.Align.END;
        fullname_label.halign = Gtk.Align.START;

        status_label = new Gtk.Label (null);
        status_label.valign = Gtk.Align.START;
        status_label.halign = Gtk.Align.START;

        if (user == null) {
            avatar = new Hdy.Avatar (ICON_SIZE, null, false);
            // We want to use the user's accent, not a random color
            unowned Gtk.StyleContext avatar_context = avatar.get_style_context ();
            avatar_context.remove_class ("color1");
            avatar_context.remove_class ("color2");
            avatar_context.remove_class ("color3");
            avatar_context.remove_class ("color4");
            avatar_context.remove_class ("color5");
            avatar_context.remove_class ("color6");
            avatar_context.remove_class ("color7");
            avatar_context.remove_class ("color8");
            avatar_context.remove_class ("color9");
            avatar_context.remove_class ("color10");
            avatar_context.remove_class ("color11");
            avatar_context.remove_class ("color12");
            avatar_context.remove_class ("color13");
            avatar_context.remove_class ("color14");
        } else {
            avatar = new Hdy.Avatar (ICON_SIZE, fullname, true);
            avatar.set_image_load_func (avatar_image_load_func);

            user.changed.connect (() => {
                update ();
                update_state.begin ();
            });

            user.bind_property ("locked", this, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
            user.bind_property ("locked", this, "no-show-all", BindingFlags.SYNC_CREATE);
            user.bind_property ("real-name", avatar, "text", BindingFlags.SYNC_CREATE);

            update ();
        }

        var grid = new Gtk.Grid () {
            column_spacing = 12
        };
        grid.attach (avatar, 0, 0, 3, 3);
        grid.attach (fullname_label, 3, 0, 2, 1);
        grid.attach (status_label, 3, 1, 2, 1);

        get_style_context ().add_class ("menuitem");
        add (grid);

        update_state.begin ();
    }

    private Gdk.Pixbuf? avatar_image_load_func (int size) {
        try {
            var pixbuf = new Gdk.Pixbuf.from_file (user.get_icon_file ());
            return pixbuf.scale_simple (size, size, Gdk.InterpType.BILINEAR);
        } catch (Error e) {
            debug (e.message);
            return null;
        }
    }

    // For some reason Act.User.is_logged_in () does not work
    public async UserState get_user_state () {
        if (is_guest) {
            return yield Services.UserManager.get_guest_state ();
        } else {
            return yield Services.UserManager.get_user_state (user.get_uid ());
        }
    }

    private void update () {
        if (user == null) {
            return;
        }

        fullname_label.label = "<b>%s</b>".printf (user.real_name);
        avatar.set_image_load_func (avatar_image_load_func);
    }

    public async void update_state () {
        state = yield get_user_state ();

        selectable = state != UserState.ACTIVE;
        activatable = state != UserState.ACTIVE;

        if (state == UserState.ONLINE || state == UserState.ACTIVE) {
            status_label.label = _("Logged in");
        } else {
            status_label.label = _("Logged out");
        }

        changed ();
        show_all ();
    }

    public override bool draw (Cairo.Context ctx) {
        if (!get_selectable ()) {
            get_style_context ().set_state (Gtk.StateFlags.NORMAL);
        }

        return base.draw (ctx);
    }
}

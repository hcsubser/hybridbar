/*
 * Copyright 2015-2020 elementary, Inc. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class Network.WifiMenuItem : Gtk.ListBoxRow {
    private List<NM.AccessPoint> _ap;
    public signal void user_action ();
    public GLib.Bytes ssid {
        get {
            return _tmp_ap.get_ssid ();
        }
    }

    public Network.State state { get; set; default=Network.State.DISCONNECTED; }

    public uint8 strength {
        get {
            uint8 strength = 0;
            foreach (var ap in _ap) {
                strength = uint8.max (strength, ap.get_strength ());
            }
            return strength;
        }
    }

    public NM.AccessPoint ap { get { return _tmp_ap; } }
    private NM.AccessPoint _tmp_ap;

    private Gtk.RadioButton radio_button;
    private Gtk.Image img_strength;
    private Gtk.Image lock_img;
    private Gtk.Image error_img;
    private Gtk.Spinner spinner;
    private Gtk.Label label;

    public WifiMenuItem (NM.AccessPoint ap, WifiMenuItem? previous = null) {
        label = new Gtk.Label (null) {
            ellipsize = Pango.EllipsizeMode.MIDDLE
        };

        radio_button = new Gtk.RadioButton (null) {
            hexpand = true
        };
        radio_button.add (label);

        if (previous != null) {
            radio_button.set_group (previous.get_group ());
        }

        img_strength = new Gtk.Image () {
            icon_size = Gtk.IconSize.MENU
        };

        lock_img = new Gtk.Image.from_icon_name ("channel-insecure-symbolic", Gtk.IconSize.MENU);

        error_img = new Gtk.Image.from_icon_name ("process-error-symbolic", Gtk.IconSize.MENU) {
            tooltip_text = _("Unable to connect")
        };

        spinner = new Gtk.Spinner () {
            no_show_all = true,
            visible = false
        };
        spinner.start ();

        var grid = new Gtk.Grid () {
            column_spacing = 6
        };
        grid.add (radio_button);
        grid.add (spinner);
        grid.add (error_img);
        grid.add (lock_img);
        grid.add (img_strength);

        _ap = new List<NM.AccessPoint> ();

        /* Adding the access point triggers update */
        add_ap (ap);

        notify["state"].connect (update);
        radio_button.notify["active"].connect (update);

        radio_button.button_release_event.connect ((b, ev) => {
            user_action ();
            return false;
        });

        add (grid);

    }

    /**
     * Only used for an item which is not displayed: hacky way to have no radio button selected.
     **/
    public WifiMenuItem.blank () {
        radio_button = new Gtk.RadioButton (null);
    }

    class construct {
        set_css_name (Gtk.STYLE_CLASS_MENUITEM);
    }

    private void update_tmp_ap () {
        uint8 strength = 0;
        foreach (var ap in _ap) {
            _tmp_ap = strength > ap.get_strength () ? _tmp_ap : ap;
            strength = uint8.max (strength, ap.get_strength ());
        }
    }

    public void set_active (bool active) {
        radio_button.set_active (active);
    }

    private unowned SList get_group () {
        return radio_button.get_group ();
    }

    private void update () {
        label.label = NM.Utils.ssid_to_utf8 (ap.get_ssid ().get_data ());

        img_strength.icon_name = get_strength_symbolic_icon ();
        img_strength.show_all ();

        var flags = ap.get_wpa_flags () | ap.get_rsn_flags ();
        var is_secured = false;
        if (NM.@80211ApSecurityFlags.GROUP_WEP40 in flags) {
            is_secured = true;
            tooltip_text = _("40/64-bit WEP encrypted");
        } else if (NM.@80211ApSecurityFlags.GROUP_WEP104 in flags) {
            is_secured = true;
            tooltip_text = _("104/128-bit WEP encrypted");
        } else if (NM.@80211ApSecurityFlags.KEY_MGMT_PSK in flags) {
            is_secured = true;
            tooltip_text = _("WPA encrypted");
        } else if (flags != NM.@80211ApSecurityFlags.NONE) {
            is_secured = true;
            tooltip_text = _("Encrypted");
        } else {
            tooltip_text = _("Unsecured");
        }

        lock_img.visible = !is_secured;
        lock_img.no_show_all = !lock_img.visible;

        hide_item (error_img);
        hide_item (spinner);

        switch (state) {
        case State.FAILED_WIFI:
            show_item (error_img);
            break;
        case State.CONNECTING_WIFI:
            show_item (spinner);
            if (!radio_button.active) {
                critical ("An access point is being connected but not active.");
            }
            break;
        }
    }

    private void show_item (Gtk.Widget w) {
        w.visible = true;
        w.no_show_all = !w.visible;
    }

    private void hide_item (Gtk.Widget w) {
        w.visible = false;
        w.no_show_all = !w.visible;
        w.hide ();
    }

    public void add_ap (NM.AccessPoint ap) {
        _ap.append (ap);
        update_tmp_ap ();

        update ();
    }

    private const string BASE_ICON_NAME = "network-wireless-signal-";
    private const string SYMBOLIC = "-symbolic";
    private unowned string get_strength_symbolic_icon () {
        if (strength < 30) {
            return BASE_ICON_NAME + "weak" + SYMBOLIC;
        } else if (strength < 55) {
            return BASE_ICON_NAME + "ok" + SYMBOLIC;
        } else if (strength < 80) {
            return BASE_ICON_NAME + "good" + SYMBOLIC;
        } else {
            return BASE_ICON_NAME + "excellent" + SYMBOLIC;
        }
    }

    public bool remove_ap (NM.AccessPoint ap) {
        _ap.remove (ap);
        update_tmp_ap ();
        return _ap.length () > 0;
    }
}

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
*
*/

public class Network.WifiInterface : Network.WidgetNMInterface {
    public NM.Client nm_client { get; construct; }

    public NM.DeviceWifi? wifi_device;
    public bool hidden_sensitivity { get; set; default = true; }

    public string active_ap_name { get; private set; }

    private Wingpanel.Widgets.Switch wifi_item;
    private Gtk.Revealer revealer;

    private RFKillManager rfkill;
    private NM.AccessPoint? active_ap;
    private Gtk.ListBox wifi_list;
    private WifiMenuItem? active_wifi_item;
    private WifiMenuItem? blank_item = null;
    private Gtk.Stack placeholder;

    private bool locked;
    private bool software_locked;
    private bool hardware_locked;

    private uint timeout_scan = 0;
    private Cancellable wifi_scan_cancellable = new Cancellable ();

    public WifiInterface (NM.Client nm_client, NM.Device? _device) {
        Object (nm_client: nm_client);

        device = _device;

        wifi_device = (NM.DeviceWifi) device;
        blank_item = new WifiMenuItem.blank ();
        active_wifi_item = null;

        /* Monitor killswitch status */
        rfkill = new RFKillManager ();
        rfkill.open ();
        rfkill.device_added.connect (update);
        rfkill.device_changed.connect (update);
        rfkill.device_deleted.connect (update);

        wifi_device.notify["active-access-point"].connect (update);
        wifi_device.access_point_added.connect (access_point_added_cb);
        wifi_device.access_point_removed.connect (access_point_removed_cb);
        wifi_device.state_changed.connect (update);

        var aps = wifi_device.get_access_points ();
        if (aps != null && aps.length > 0) {
            aps.foreach (access_point_added_cb);
        }

        update ();

        wifi_item.caption = display_title;
        notify["display-title"].connect ( () => {
            wifi_item.caption = display_title;
        });

        wifi_item.notify["active"].connect (() => {
            var active = wifi_item.active;
            if (active != !software_locked) {
                rfkill.set_software_lock (RFKillDeviceType.WLAN, !active);
                nm_client.wireless_set_enabled (active);
            }
        });
    }

    construct {
        var no_aps = new PlaceholderLabel (_("No Access Points Available"));

        var scanning = new PlaceholderLabel (_("Scanning for Access Points…")) {
            halign = Gtk.Align.START,
            hexpand = true
        };

        var spinner = new Gtk.Spinner ();
        spinner.start ();

        var scanning_box = new Gtk.Grid () {
            column_spacing = 6,
            valign = Gtk.Align.CENTER
        };
        scanning_box.add (scanning);
        scanning_box.add (spinner);

        placeholder = new Gtk.Stack () {
            margin_end = 12,
            margin_start = 12
        };
        placeholder.add_named (no_aps, "no-aps");
        placeholder.add_named (scanning_box, "scanning");
        placeholder.visible_child_name = "no-aps";
        placeholder.show_all ();

        wifi_list = new Gtk.ListBox ();
        wifi_list.set_sort_func (sort_func);
        wifi_list.set_placeholder (placeholder);

        wifi_item = new Wingpanel.Widgets.Switch ("");
        //wifi_item.get_style_context ().add_class (Granite.STYLE_CLASS_H4_LABEL);

        var scrolled_box = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            max_content_height = 512,
            propagate_natural_height = true
        };
        scrolled_box.add (wifi_list);

        revealer = new Gtk.Revealer ();
        revealer.add (scrolled_box);

        orientation = Gtk.Orientation.VERTICAL;
        pack_start (wifi_item);
        pack_start (revealer);
    }

    public override void update_name (int count) {
        if (count <= 1) {
            display_title = _("Wireless");
        } else {
            display_title = device.get_description ();
        }
    }

    public override void update () {
        switch (wifi_device.state) {
        case NM.DeviceState.UNKNOWN:
        case NM.DeviceState.UNMANAGED:
        case NM.DeviceState.FAILED:
            state = State.FAILED_WIFI;
            if (active_wifi_item != null) {
                active_wifi_item.state = state;
            }
            cancel_scan ();
            break;

        case NM.DeviceState.DEACTIVATING:
        case NM.DeviceState.UNAVAILABLE:
            cancel_scan ();
            state = State.DISCONNECTED;
            break;
        case NM.DeviceState.DISCONNECTED:
            set_scan_placeholder ();
            state = State.DISCONNECTED;
            break;

        case NM.DeviceState.PREPARE:
        case NM.DeviceState.CONFIG:
        case NM.DeviceState.NEED_AUTH:
        case NM.DeviceState.IP_CONFIG:
        case NM.DeviceState.IP_CHECK:
        case NM.DeviceState.SECONDARIES:
            set_scan_placeholder ();
            state = State.CONNECTING_WIFI;
            break;

        case NM.DeviceState.ACTIVATED:
            set_scan_placeholder ();

            /* That can happen if active_ap has not been added yet, at startup. */
            if (active_ap != null) {
                state = strength_to_state (active_ap.get_strength ());
            } else {
                state = State.CONNECTED_WIFI_WEAK;
            }
            break;
        }

        debug ("New network state: %s", state.to_string ());

        /* Wifi */
        software_locked = false;
        hardware_locked = false;
        foreach (var device in rfkill.get_devices ()) {
            if (device.device_type != RFKillDeviceType.WLAN) {
                continue;
            }

            if (device.software_lock) {
                software_locked = true;
            }

            if (device.hardware_lock) {
                hardware_locked = true;
            }
        }

        locked = hardware_locked || software_locked;

        update_active_ap ();

        base.update ();

        wifi_item.set_sensitive (!hardware_locked);
        wifi_item.active = !locked;

        active_ap = wifi_device.get_active_access_point ();

        if (wifi_device.state == NM.DeviceState.UNAVAILABLE || state == Network.State.FAILED_WIFI) {
            revealer.reveal_child = false;
            hidden_sensitivity = false;
        } else {
            revealer.reveal_child = true;
            hidden_sensitivity = true;
        }
    }

    private void wifi_activate_cb (WifiMenuItem i) {
        if (device == null) {
            return;
        }

        /* Do not activate connection if it is already activated */
        if (wifi_device.get_active_access_point () == i.ap) {
            return;
        }

        // See if we already have a connection configured for this AP and try connecting if so
        var connections = nm_client.get_connections ();
        var device_connections = wifi_device.filter_connections (connections);
        var ap_connections = i.ap.filter_connections (device_connections);

        var valid_connection = get_valid_connection (i.ap, ap_connections);
        if (valid_connection != null) {
            nm_client.activate_connection_async.begin (valid_connection, wifi_device, i.ap.get_path (), null, null);
            return;
        }

        var flags = i.ap.get_wpa_flags () | i.ap.get_rsn_flags ();
        if (flags != NM.@80211ApSecurityFlags.NONE) {
            var connection = NM.SimpleConnection.new ();
            var s_con = new NM.SettingConnection ();
            s_con.uuid = NM.Utils.uuid_generate ();
            connection.add_setting (s_con);

            var s_wifi = new NM.SettingWireless ();
            s_wifi.ssid = i.ap.get_ssid ();
            connection.add_setting (s_wifi);

            // If the AP is WPA[2]-Enterprise then we need to set up a minimal 802.1x setting before
            // prompting the user to configure the authentication, otherwise, the dialog works out
            // what sort of credentials to prompt for automatically
            if (NM.@80211ApSecurityFlags.KEY_MGMT_802_1X in flags) {
                var s_wsec = new NM.SettingWirelessSecurity ();
                s_wsec.key_mgmt = "wpa-eap";
                connection.add_setting (s_wsec);

                var s_8021x = new NM.Setting8021x ();
                s_8021x.add_eap_method ("ttls");
                s_8021x.phase2_auth = "mschapv2";
                connection.add_setting (s_8021x);
            }

            // In theory, we could just activate normal WEP/WPA connections without spawning a WifiDialog
            // and NM would create its own dialog, but Mutter's focus stealing prevention often hides it
            // so we spawn our own
            var wifi_dialog = new NMA.WifiDialog (nm_client, connection, wifi_device, i.ap, false) {
                deletable = false
            };
            wifi_dialog.transient_for = (Gtk.Window) get_toplevel ();

            wifi_dialog.response.connect ((response) => {
                if (response == Gtk.ResponseType.OK) {
                    connect_to_network.begin (wifi_dialog);
                }
            });

            wifi_dialog.run ();
            wifi_dialog.destroy ();
        } else {
            nm_client.add_and_activate_connection_async.begin (
                NM.SimpleConnection.new (),
                wifi_device,
                i.ap.get_path (),
                null,
                (obj, res) => {
                    try {
                        nm_client.add_and_activate_connection_async.end (res);
                    } catch (Error error) {
                        warning (error.message);
                    }
                }
            );
        }

        /* Do an update at the next iteration of the main loop, so as every
         * signal is flushed (for instance signals responsible for radio button
         * checked) */
        Idle.add (() => { update (); return false; });
    }

    public void start_scanning () {
        wifi_scan_cancellable.reset ();
        wifi_device.request_scan_async.begin (wifi_scan_cancellable, null);
    }

    public void cancel_scanning () {
        wifi_scan_cancellable.cancel ();
    }

    private NM.Connection? get_valid_connection (NM.AccessPoint ap, GenericArray<NM.Connection> ap_connections) {
        for (int i = 0; i < ap_connections.length; i++) {
            weak NM.Connection connection = ap_connections.get (i);
            if (ap.connection_valid (connection)) {
                return connection;
            }
        }

        return null;
    }

    public void connect_to_hidden () {
        var hidden_dialog = new NMA.WifiDialog.for_other (nm_client) {
            deletable = false
        };
        hidden_dialog.transient_for = (Gtk.Window) get_toplevel ();

        hidden_dialog.response.connect ((response) => {
            if (response == Gtk.ResponseType.OK) {
                connect_to_network.begin (hidden_dialog);
            }
        });

        hidden_dialog.run ();
        hidden_dialog.destroy ();
    }

    private async void connect_to_network (NMA.WifiDialog wifi_dialog) {
        NM.Connection? fuzzy = null;
        NM.Device dialog_device;
        NM.AccessPoint? dialog_ap = null;
        var dialog_connection = wifi_dialog.get_connection (out dialog_device, out dialog_ap);

        nm_client.get_connections ().foreach ((possible) => {
            if (dialog_connection.compare (possible, NM.SettingCompareFlags.FUZZY | NM.SettingCompareFlags.IGNORE_ID)) {
                fuzzy = possible;
            }
        });

        string? path = null;
        if (dialog_ap != null) {
            path = dialog_ap.get_path ();
        }

        if (fuzzy != null) {
            try {
                yield nm_client.activate_connection_async (fuzzy, wifi_device, path, null);
            } catch (Error error) {
                critical (error.message);
            }
        } else {
            string? mode = null;
            unowned NM.SettingWireless setting_wireless = dialog_connection.get_setting_wireless ();
            if (setting_wireless != null) {
                mode = setting_wireless.get_mode ();
            }

            if (mode == "adhoc") {
                NM.SettingConnection connection_setting = dialog_connection.get_setting_connection ();
                if (connection_setting == null) {
                    connection_setting = new NM.SettingConnection ();
                }

                dialog_connection.add_setting (connection_setting);
            }

            try {
                yield nm_client.add_and_activate_connection_async (dialog_connection, dialog_device, path, null);
            } catch (Error error) {
                critical (error.message);
            }
        }
    }

    private class PlaceholderLabel : Gtk.Label {
        public PlaceholderLabel (string label) {
            Object (label: label);
        }

        construct {
            justify = Gtk.Justification.CENTER;
            max_width_chars = 30;
            use_markup = true;
            visible = true;
            wrap_mode = Pango.WrapMode.WORD_CHAR;
            wrap = true;
        }
    }

    private void access_point_added_cb (Object ap_) {
        NM.AccessPoint ap = (NM.AccessPoint)ap_;
        WifiMenuItem? previous_wifi_item = blank_item;
        unowned GLib.Bytes ap_ssid = ap.ssid;

        bool found = false;

        foreach (weak Gtk.Widget w in wifi_list.get_children ()) {
            var menu_item = (WifiMenuItem) w;

            var menu_ssid = menu_item.ssid;
            if (menu_ssid != null && ap.ssid != null && ap.ssid.compare (menu_ssid) == 0) {
                found = true;
                menu_item.add_ap (ap);
                break;
            }

            previous_wifi_item = menu_item;
        }

        /* Sometimes network manager sends a (fake?) AP without a valid ssid. */
        if (!found && ap_ssid != null) {
            var item = new WifiMenuItem (ap, previous_wifi_item);

            previous_wifi_item = item;
            item.set_visible (true);
            item.user_action.connect (wifi_activate_cb);

            wifi_list.add (item);
            wifi_list.show_all ();

            update ();
        }

    }

    private void update_active_ap () {
        debug ("Update active AP");

        active_ap = wifi_device.get_active_access_point ();

        if (active_wifi_item != null) {
            if (active_wifi_item.state == Network.State.CONNECTING_WIFI) {
                active_wifi_item.state = Network.State.DISCONNECTED;
            }
            active_wifi_item = null;
        }

        if (active_ap == null) {
            debug ("No active AP");
            blank_item.set_active (true);
        } else {
            unowned GLib.Bytes active_ap_ssid = active_ap.ssid;
            active_ap_name = NM.Utils.ssid_to_utf8 (active_ap_ssid.get_data ());
            debug ("Active ap: %s", active_ap_name);

            bool found = false;
            foreach (weak Gtk.Widget w in wifi_list.get_children ()) {
                var menu_item = (WifiMenuItem) w;

                if (active_ap_ssid.compare (menu_item.ssid) == 0) {
                    found = true;
                    menu_item.set_active (true);
                    active_wifi_item = menu_item;
                    active_wifi_item.state = state;
                }
            }

            /* This can happen at start, when the access point list is populated. */
            if (!found) {
                debug ("Active AP not added");
            }
        }
    }

    private void access_point_removed_cb (Object ap_) {
        NM.AccessPoint ap = (NM.AccessPoint)ap_;
        if (ap.ssid == null) {
          update ();
          return;
        }

        WifiMenuItem found_item = null;

        foreach (weak Gtk.Widget w in wifi_list.get_children ()) {
            var menu_item = (WifiMenuItem) w;

            assert (menu_item != null);

            if (ap.ssid.compare (menu_item.ssid) == 0) {
                found_item = menu_item;
                break;
            }
        }

        if (found_item == null) {
            critical ("Couldn't remove an access point which has not been added.");
        } else {
            if (!found_item.remove_ap (ap)) {
                found_item.destroy ();
            }
        }

        update ();
    }

    private Network.State strength_to_state (uint8 strength) {
        if (strength < 30) {
            return Network.State.CONNECTED_WIFI_WEAK;
        } else if (strength < 55) {
            return Network.State.CONNECTED_WIFI_OK;
        } else if (strength < 80) {
            return Network.State.CONNECTED_WIFI_GOOD;
        } else {
            return Network.State.CONNECTED_WIFI_EXCELLENT;
        }
    }

    private void cancel_scan () {
        if (timeout_scan > 0) {
            Source.remove (timeout_scan);
            timeout_scan = 0;
        }
    }

    private void set_scan_placeholder () {
        // this state is the previous state (because this method is called before putting the new state)
        if (state == State.DISCONNECTED) {
            placeholder.visible_child_name = "scanning";
            cancel_scan ();
            wifi_device.request_scan_async.begin (null, null);
            timeout_scan = Timeout.add (5000, () => {
                timeout_scan = 0;
                placeholder.visible_child_name = "no-aps";
                return false;
            });
        }
    }

    private int sort_func (Gtk.ListBoxRow r1, Gtk.ListBoxRow r2) {
        if (r1 == null || r2 == null) {
            return 0;
        }

        var w1 = (WifiMenuItem)r1;
        var w2 = (WifiMenuItem)r2;

        return w2.strength - w1.strength;
    }
}

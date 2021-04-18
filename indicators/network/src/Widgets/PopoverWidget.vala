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

public class Network.Widgets.PopoverWidget : Gtk.Grid {
    private NM.Client nm_client;
    private NM.VpnConnection? active_vpn_connection = null;

    private GLib.List<WidgetNMInterface>? network_interface;

    public bool secure { private set; get; default = false; }
    public string? extra_info { private set; get; default = null; }
    public Network.State state { private set; get; default = Network.State.CONNECTING_WIRED; }

    public Gtk.Box other_box { get; private set; }
    public Gtk.Box wifi_box { get; private set; }
    private Gtk.Box vpn_box;
    private Gtk.ModelButton hidden_item;

    public bool is_in_session { get; construct; }

    public signal void settings_shown ();

    public PopoverWidget (bool is_in_session) {
        Object (is_in_session: is_in_session);
    }

    construct {
        network_interface = new GLib.List<WidgetNMInterface> ();

        orientation = Gtk.Orientation.VERTICAL;

        other_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        wifi_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vpn_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        add (other_box);
        add (wifi_box);
        add (vpn_box);

        if (is_in_session) {
            hidden_item = new Gtk.ModelButton ();
            hidden_item.text = _("Connect to Hidden Network…");
            hidden_item.no_show_all = true;

            var show_settings_button = new Gtk.ModelButton ();
            show_settings_button.text = _("Network Settings…");

            add (hidden_item);
            add (show_settings_button);

            show_settings_button.clicked.connect (show_settings);
        }

        /* Monitor network manager */
        try {
            nm_client = new NM.Client ();
        } catch (Error e) {
            critical (e.message);
        }

        nm_client.notify["active-connections"].connect (update_vpn_connection);

        nm_client.device_added.connect (device_added_cb);
        nm_client.device_removed.connect (device_removed_cb);

        nm_client.notify["networking-enabled"].connect (update_state);

        var devices = nm_client.get_devices ();
        for (var i = 0; i < devices.length; i++)
            device_added_cb (devices.get (i));

        // Vpn interface
        WidgetNMInterface widget_interface = new VpnInterface (nm_client);
        network_interface.append (widget_interface);
        add_interface (widget_interface);
        widget_interface.notify["state"].connect (update_state);

        show_all ();
        update_vpn_connection ();

        hidden_item.clicked.connect (() => {
            bool found = false;
            wifi_box.get_children ().foreach ((child) => {
                if (child is Network.WifiInterface && ((Network.WifiInterface) child).hidden_sensitivity && !found) {
                    ((Network.WifiInterface) child).connect_to_hidden ();
                    found = true;
                }
            });
        });
    }

    private void add_interface (WidgetNMInterface widget_interface) {
        Gtk.Box container_box = other_box;

        if (widget_interface is Network.WifiInterface) {
            container_box = wifi_box;
            hidden_item.no_show_all = false;
            hidden_item.show_all ();

            ((Network.WifiInterface) widget_interface).notify["hidden-sensitivity"].connect (() => {
                bool hidden_sensitivity = false;

                wifi_box.get_children ().foreach ((child) => {
                    if (child is Network.WifiInterface) {
                        hidden_sensitivity = hidden_sensitivity || ((Network.WifiInterface) child).hidden_sensitivity;
                    }

                    hidden_item.sensitive = hidden_sensitivity;
                });
            });
        }

        if (widget_interface is Network.VpnInterface) {
            container_box = vpn_box;
        }

        if (is_in_session && get_children ().length () > 0) {
            container_box.pack_end (widget_interface.sep);
        }

        container_box.pack_end (widget_interface);
    }

    public void opened () {
        foreach (var widget in wifi_box.get_children ()) {
            if (widget is WifiInterface) {
                ((WifiInterface)widget).start_scanning ();
            }
        }
    }

    public void closed () {
        foreach (var widget in wifi_box.get_children ()) {
            if (widget is WifiInterface) {
                ((WifiInterface)widget).cancel_scanning ();
            }
        }
    }

    private void show_settings () {
        if (is_in_session) {
            try {
                AppInfo.launch_default_for_uri ("settings://network", null);
            } catch (Error e) {
                warning ("Failed to open network settings: %s", e.message);
            }

            settings_shown ();
        }
    }

    private void device_removed_cb (NM.Device device) {
        foreach (var widget_interface in network_interface) {
            if (widget_interface.is_device (device)) {
                network_interface.remove (widget_interface);

                widget_interface.sep.destroy ();
                widget_interface.destroy ();
                break;
            }
        }

        update_interfaces_names ();
        update_state ();
    }

    private void update_interfaces_names () {
        var count_type = new Gee.HashMap<string, int?> ();
        foreach (var iface in network_interface) {
            var type = iface.get_type ().name ();
            if (count_type.has_key (type)) {
                count_type[type] = count_type[type] + 1;
            } else {
                count_type[type] = 1;
            }
        }

        foreach (var iface in network_interface) {
            var type = iface.get_type ().name ();
            iface.update_name (count_type [type]);
        }
    }

    private void device_added_cb (NM.Device device) {
        if (device.get_iface ().has_prefix ("vmnet") ||
            device.get_iface ().has_prefix ("lo") ||
            device.get_iface ().has_prefix ("veth") ||
            device.get_iface ().has_prefix ("vboxnet")) {
            return;
        }

        WidgetNMInterface? widget_interface = null;

        if (device is NM.DeviceWifi) {
            widget_interface = new WifiInterface (nm_client, device);
            debug ("Wifi interface added");
        } else if (device is NM.DeviceEthernet) {
            widget_interface = new EtherInterface (nm_client, device);
            debug ("Wired interface added");
        } else if (device is NM.DeviceModem) {
            widget_interface = new ModemInterface (nm_client, device);
            debug ("Modem interface added");
        } else {
            debug ("Unknown device: %s\n", device.get_device_type ().to_string ());
        }

        if (widget_interface != null) {
            // Implementation call
            network_interface.append (widget_interface);
            add_interface (widget_interface);
            widget_interface.notify["state"].connect (update_state);
            widget_interface.notify["extra-info"].connect (update_state);

        }

        update_interfaces_names ();

        foreach (var inter in network_interface) {
            inter.update ();
        }

        update_state ();
        show_all ();
    }

    private void update_state () {
        if (!nm_client.networking_get_enabled ()) {
            state = Network.State.DISCONNECTED_AIRPLANE_MODE;
        } else {
            var next_state = Network.State.DISCONNECTED;
            var best_score = int.MAX;

            foreach (var inter in network_interface) {
                var score = inter.state.get_priority ();

                if (score < best_score) {
                    next_state = inter.state;
                    best_score = score;
                    if (inter is Network.ModemInterface) {
                        extra_info = ((Network.ModemInterface) inter).extra_info;
                    }
                }
            }

            state = next_state;
        }
    }

    private void update_vpn_connection () {
        active_vpn_connection = null;

        nm_client.get_active_connections ().foreach ((ac) => {
            if (active_vpn_connection == null && ac.get_vpn ()) {
                active_vpn_connection = (NM.VpnConnection)ac;
                update_vpn_state (active_vpn_connection.get_vpn_state ());
                active_vpn_connection.vpn_state_changed.connect (() => {
                    update_vpn_state (active_vpn_connection.get_vpn_state ());
                });
            }
        });
    }

    private void update_vpn_state (NM.VpnConnectionState state) {
        switch (state) {
            case NM.VpnConnectionState.DISCONNECTED:
            case NM.VpnConnectionState.PREPARE:
            case NM.VpnConnectionState.IP_CONFIG_GET:
            case NM.VpnConnectionState.CONNECT:
            case NM.VpnConnectionState.FAILED:
                secure = false;
                break;
            case NM.VpnConnectionState.ACTIVATED:
                secure = true;
                break;
        }
    }
}

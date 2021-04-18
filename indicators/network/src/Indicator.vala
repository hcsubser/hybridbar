/*
* Copyright (c) 2015-2018 elementary LLC (http://launchpad.net/wingpanel-indicator-network)
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

public class Network.Indicator : Wingpanel.Indicator {
    Network.Widgets.DisplayWidget? display_widget = null;
    Network.Widgets.PopoverWidget? popover_widget = null;

    NetworkMonitor network_monitor;

    public bool is_in_session { get; set; default = false; }

    public Indicator (bool is_in_session) {
        Object (code_name: Wingpanel.Indicator.NETWORK,
                is_in_session: is_in_session,
                visible: true);

        display_widget = new Widgets.DisplayWidget ();

        popover_widget = new Widgets.PopoverWidget (is_in_session);
        popover_widget.notify["state"].connect (on_state_changed);
        popover_widget.notify["secure"].connect (on_state_changed);
        popover_widget.notify["extra-info"].connect (on_state_changed);
        popover_widget.settings_shown.connect (() => { close (); });

        update_tooltip ();
        on_state_changed ();
        start_monitor ();
    }

    public override Gtk.Widget get_display_widget () {
        return display_widget;
    }

    public override Gtk.Widget? get_widget () {
        return popover_widget;
    }

    void on_state_changed () {
        assert (popover_widget != null);
        assert (display_widget != null);

        display_widget.update_state (popover_widget.state, popover_widget.secure, popover_widget.extra_info);
    }

    private void start_monitor () {
        network_monitor = NetworkMonitor.get_default ();

        network_monitor.network_changed.connect ((availabe) => {
            if (!is_in_session) {
                return;
            }

            if (network_monitor.get_connectivity () == NetworkConnectivity.FULL || network_monitor.get_connectivity () == NetworkConnectivity.PORTAL) {
                try {
                    var appinfo = AppInfo.create_from_commandline ("io.elementary.capnet-assist", null, AppInfoCreateFlags.NONE);
                    appinfo.launch (null, null);
                } catch (Error e) {
                    warning ("%s\n", e.message);
                }
            }

            update_tooltip ();
        });
    }

    public override void opened () {
        if (popover_widget != null) {
            popover_widget.opened ();
        }
    }

    public override void closed () {
        if (popover_widget != null) {
            popover_widget.closed ();
        }
    }

    private void update_tooltip () {
        switch (popover_widget.state) {
            case Network.State.CONNECTING_WIRED:
                /* If there's only one active ethernet connection,
                we get back the string "Wired". We won't want to
                show the user Connecting to "Wired" so we'll have
                to show them something else if we get back
                "Wired" from get_active_wired_name () */

                string active_wired_name = get_active_wired_name ();

                if (active_wired_name == _("Wired")) {
                    display_widget.tooltip_markup = _("Connecting to wired network");
                } else {
                    display_widget.tooltip_markup = _("Connecting to “%s”").printf (active_wired_name);
                }
                break;
            case Network.State.CONNECTING_WIFI:
            case Network.State.CONNECTING_MOBILE:
                display_widget.tooltip_markup = _("Connecting to “%s”").printf (get_active_wifi_name ());
                break;
            case Network.State.CONNECTED_WIRED:
                string active_wired_name = get_active_wired_name ();

                if (active_wired_name == _("Wired")) {
                    display_widget.tooltip_markup = _("Connected to wired network");
                } else {
                    display_widget.tooltip_markup = _("Connected to “%s”").printf (active_wired_name);
                }
                break;
            case Network.State.CONNECTED_WIFI:
            case Network.State.CONNECTED_WIFI_WEAK:
            case Network.State.CONNECTED_WIFI_OK:
            case Network.State.CONNECTED_WIFI_GOOD:
            case Network.State.CONNECTED_WIFI_EXCELLENT:
            case Network.State.CONNECTED_MOBILE_WEAK:
            case Network.State.CONNECTED_MOBILE_OK:
            case Network.State.CONNECTED_MOBILE_GOOD:
            case Network.State.CONNECTED_MOBILE_EXCELLENT:
                display_widget.tooltip_markup = _("Connected to “%s”").printf (get_active_wifi_name ());
                break;
            case Network.State.FAILED_WIRED:
            case Network.State.FAILED_WIFI:
            case Network.State.FAILED_VPN:
            case Network.State.FAILED_MOBILE:
                display_widget.tooltip_markup = _("Failed to connect");
                break;
            case Network.State.DISCONNECTED_WIRED:
            case Network.State.DISCONNECTED_AIRPLANE_MODE:
                display_widget.tooltip_markup = _("Disconnected");
                break;
            default:
                display_widget.tooltip_markup = _("Not connected");
                break;
        }
    }

    private string get_active_wired_name () {
        foreach (unowned Gtk.Widget child in popover_widget.other_box.get_children ()) {
            if (child is Network.EtherInterface) {
                var active_wired_name = ((Network.EtherInterface) child).display_title;
                debug ("Active network (Wired): %s".printf (active_wired_name));
                return active_wired_name;
            }
        }

        return _("unknown network");
    }

    private string get_active_wifi_name () {
        foreach (unowned Gtk.Widget child in popover_widget.wifi_box.get_children ()) {
            if (child is Network.WifiInterface) {
                var active_wifi_name = ((Network.WifiInterface) child).active_ap_name;
                debug ("Active network (WiFi): %s".printf (active_wifi_name));
                return active_wifi_name;
            }
        }

        return _("unknown network");
    }
}

public Wingpanel.Indicator get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    debug ("Activating Network Indicator");
    var indicator = new Network.Indicator (server_type == Wingpanel.IndicatorManager.ServerType.SESSION);
    return indicator;
}

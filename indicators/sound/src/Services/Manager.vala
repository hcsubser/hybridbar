/*
 * Copyright (c) 2015-2017 elementary LLC. (http://launchpad.net/wingpanel-indicator-sound)
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
 * License along with this program; If not, see <http://www.gnu.org/licenses/>.
 *
 */

public class Sound.Services.ObjectManager : Object {
    public signal void global_state_changed (bool enabled, bool connected);
    public signal void media_player_added (Services.MediaPlayer media_player, string name, string icon);
    public signal void media_player_removed (Services.MediaPlayer media_player);
    public signal void media_player_status_changed (string status, string title, string album);

    public bool has_object { get; private set; default = false; }
    public string media_player_status { get; private set; default = "stopped";}
    public string current_track_title { get; private set; default = "Not playing";}
    public string current_track_artist { get; private set;}

    private GLib.DBusObjectManagerClient object_manager;

    public ObjectManager () { }

    construct {
        create_manager.begin ();
    }

    private async void create_manager () {
        try {
            object_manager = yield new GLib.DBusObjectManagerClient.for_bus.begin (
                BusType.SYSTEM,
                GLib.DBusObjectManagerClientFlags.NONE,
                "org.bluez",
                "/",
                object_manager_proxy_get_type,
                null
            );
            object_manager.get_objects ().foreach ((object) => {
                object.get_interfaces ().foreach ((iface) => on_interface_added (object, iface));
            });
            object_manager.interface_added.connect (on_interface_added);
            object_manager.interface_removed.connect (on_interface_removed);
            object_manager.object_added.connect ((object) => {
                object.get_interfaces ().foreach ((iface) => on_interface_added (object, iface));
            });
            object_manager.object_removed.connect ((object) => {
                object.get_interfaces ().foreach ((iface) => on_interface_removed (object, iface));
            });
        } catch (Error e) {
            critical (e.message);
        }
    }

    //TODO: Do not rely on this when it is possible to do it natively in Vala
    [CCode (cname="sound_services_device_proxy_get_type")]
    extern static GLib.Type get_device_proxy_type ();
    [CCode (cname="sound_services_media_player_proxy_get_type")]
    extern static GLib.Type get_media_player_proxy_type ();

    private GLib.Type object_manager_proxy_get_type (DBusObjectManagerClient manager, string object_path, string? interface_name) {
        if (interface_name == null)
            return typeof (GLib.DBusObjectProxy);

        switch (interface_name) {
            case "org.bluez.Device1":
                return get_device_proxy_type ();
            case "org.bluez.MediaPlayer1":
                return get_media_player_proxy_type ();
            default:
                return typeof (GLib.DBusProxy);
        }
    }

    private void on_interface_added (GLib.DBusObject object, GLib.DBusInterface iface) {
        if (iface is Sound.Services.MediaPlayer) {
            unowned Sound.Services.MediaPlayer media_player = (Sound.Services.MediaPlayer) iface;
            has_object = true;
            var device_object = object_manager.get_object (media_player.device);
            Sound.Services.Device cur_device = (Sound.Services.Device) device_object.get_interface ("org.bluez.Device1");
            media_player_status = media_player.track.lookup ("Title").get_string ();
            media_player_added (media_player, cur_device.name, cur_device.icon);

            ((DBusProxy) media_player).g_properties_changed.connect ((changed, invalid) => {
                var track = changed.lookup_value ("Track", VariantType.DICTIONARY);
                if (track != null) {
                    string title, artist;
                    track.lookup ("Title", "s", out title);
                    track.lookup ("Artist", "s", out artist);
                    current_track_title = title;
                    current_track_artist = artist;
                    media_player_status_changed ("", title, artist);
                }

                var status_v = changed.lookup_value ("Status", VariantType.STRING);
                if (status_v != null) {
                    string status;
                    status_v.get ("s", out status);
                    media_player_status = status;
                    media_player_status_changed (status, "", "");
                }
            });
        }
    }

    private void on_interface_removed (GLib.DBusObject object, GLib.DBusInterface iface) {
        if (iface is Sound.Services.MediaPlayer) {
            media_player_removed ((Sound.Services.MediaPlayer) iface);
            has_object = !get_media_players ().is_empty;
        }
    }

    public Gee.Collection<Sound.Services.MediaPlayer> get_media_players () {
        var players = new Gee.LinkedList<Sound.Services.MediaPlayer> ();
        object_manager.get_objects ().foreach ((object) => {
            GLib.DBusInterface? iface = object.get_interface ("org.bluez.MediaPlayer1");
            if (iface == null)
                return;

            players.add (((Sound.Services.MediaPlayer) iface));
        });

        return (owned) players;
    }
}

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

[DBus (name = "org.bluez.Device1")]
public interface Sound.Services.Device : Object {
    public abstract void cancel_pairing () throws GLib.Error;
    public abstract void connect () throws GLib.Error;
    public abstract void connect_profile (string UUID) throws GLib.Error; // vala-lint=naming-convention
    public abstract void disconnect () throws GLib.Error;
    public abstract void disconnect_profile (string UUID) throws GLib.Error; // vala-lint=naming-convention
    public abstract void pair () throws GLib.Error;

    public abstract string[] UUIDs { owned get; }
    public abstract bool blocked { get; set; }
    public abstract bool connected { get; }
    public abstract bool legacy_pairing { get; }
    public abstract bool paired { get; }
    public abstract bool trusted { get; set; }
    public abstract int16 RSSI { get; }
    public abstract ObjectPath adapter { owned get; }
    public abstract string address { owned get; }
    public abstract string alias { owned get; set; }
    public abstract string icon { owned get; }
    public abstract string modalias { owned get; }
    public abstract string name { owned get; }
    public abstract uint16 appearance { get; }
    public abstract uint32 @class { get; }
}

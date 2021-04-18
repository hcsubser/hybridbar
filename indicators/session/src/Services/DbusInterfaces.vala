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

struct UserInfo {
    uint32 uid;
    string user_name;
    ObjectPath? user_object;
}

[DBus (name = "org.gnome.SessionManager")]
interface SessionInterface : Object {
    public abstract async void logout (uint type) throws GLib.Error;
    public abstract async void reboot () throws GLib.Error;
    public abstract async void shutdown () throws GLib.Error;
}

/* Power and system control */
[DBus (name = "org.gnome.ScreenSaver")]
interface LockInterface : Object {
    public abstract void lock () throws GLib.Error;
}

[DBus (name = "org.freedesktop.login1.Manager")]
interface SystemInterface : Object {
    public abstract void suspend (bool interactive) throws GLib.Error;
    public abstract void reboot (bool interactive) throws GLib.Error;
    public abstract void power_off (bool interactive) throws GLib.Error;

    public abstract UserInfo[] list_users () throws GLib.Error;
}

[DBus (name = "org.freedesktop.login1.User")]
interface UserInterface : Object {
    public abstract string state { owned get; }
}

[DBus (name = "org.freedesktop.DisplayManager.Seat")]
interface SeatInterface : Object {
    public abstract bool has_guest_account { get; }
    public abstract void switch_to_guest (string session_name) throws GLib.Error;
    public abstract void switch_to_user (string username, string session_name) throws GLib.Error;
}

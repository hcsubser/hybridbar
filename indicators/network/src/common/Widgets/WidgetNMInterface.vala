/*
 * Copyright (c) 2015-2018 elementary LLC (https://elementary.io)
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

public abstract class Network.WidgetNMInterface : Gtk.Box {
    protected NM.Device? device;
    public Network.State state { get; protected set; default = Network.State.DISCONNECTED; }
    public string display_title { get; protected set; default = _("Unknown device"); }

    public Wingpanel.Widgets.Separator sep { get; private set; default = new Wingpanel.Widgets.Separator (); }

    public bool is_device (NM.Device device) {
        return device == this.device;
    }

    public virtual void update () {
    }

    public virtual void update_name (int count) {
        display_title = _("Unknown type: %s ").printf (device.get_description ());
    }
}

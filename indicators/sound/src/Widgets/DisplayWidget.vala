/*
* Copyright (c) 2016-2018 elementary, Inc. (https://elementary.io)
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
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

public class DisplayWidget : Gtk.Grid {
    public bool show_mic { get; set; }
    public bool mic_muted { get; set; }
    public string icon_name { get; set; }

    public signal void volume_scroll_event (Gdk.EventScroll e);
    public signal void mic_scroll_event (Gdk.EventScroll e);

    public signal void volume_press_event (Gdk.EventButton e);
    public signal void mic_press_event (Gdk.EventButton e);

    construct {
        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("io/elementary/wingpanel/sound/indicator.css");

        var volume_icon = new Gtk.Image ();
        volume_icon.pixel_size = 24;

        var mic_icon = new Gtk.Spinner ();
        mic_icon.margin_end = 18;

        var mic_style_context = mic_icon.get_style_context ();
        mic_style_context.add_provider (provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        mic_style_context.add_class ("mic-icon");

        var mic_revealer = new Gtk.Revealer ();
        mic_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT;
        mic_revealer.add (mic_icon);

        valign = Gtk.Align.CENTER;
        add (mic_revealer);
        add (volume_icon);

        /* SMOOTH_SCROLL_MASK has no effect on this widget for reasons that are not
         * entirely clear.  Only normal scroll events are received even if the SMOOTH_SCROLL_MASK
         * is set. */
        scroll_event.connect ((e) => {
            /* Ignore horizontal scrolling on wingpanel indicator */
            if (e.direction != Gdk.ScrollDirection.LEFT && e.direction != Gdk.ScrollDirection.RIGHT) {
                /* Determine whether scrolling on mic icon or not */
                if (show_mic && e.x < mic_icon.get_allocated_width () + mic_icon.margin_end) {
                    mic_scroll_event (e);
                } else {
                    volume_scroll_event (e);
                }
            }

            return true;
        });

        button_press_event.connect ((e) => {
            /* Determine whether scrolling on mic icon or not */
            if (show_mic && e.x < 24 + mic_icon.margin_end) {
                mic_press_event (e);
            } else {
                volume_press_event (e);
            }
            return Gdk.EVENT_PROPAGATE;
        });

        bind_property (
            "icon-name",
            volume_icon,
            "icon-name",
            GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE
        );
        bind_property (
            "show-mic",
            mic_revealer,
            "reveal-child",
            GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE
        );

        notify["mic-muted"].connect (() => {
            if (mic_muted) {
                mic_style_context.add_class ("disabled");
            } else {
                mic_style_context.remove_class ("disabled");
            }
        });
    }
}

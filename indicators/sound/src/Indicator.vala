/*
* Copyright 2015-2020 elementary, Inc. (https://elementary.io)
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

public class Sound.Indicator : Wingpanel.Indicator {
    public bool natural_scroll_touchpad { get; set; }
    public bool natural_scroll_mouse { get; set; }

    private DisplayWidget display_widget;
    private Gtk.Grid main_grid;
    private Widgets.MprisWidget mpris;
    private Widgets.Scale volume_scale;
    private Widgets.Scale mic_scale;
    private Wingpanel.Widgets.Separator mic_separator;
    private Notify.Notification? notification;
    private Services.VolumeControlPulse volume_control;

    private bool open = false;
    private bool mute_blocks_sound = false;
    private uint sound_was_blocked_timeout_id;

    private double max_volume = 1.0;
    private const double VOLUME_STEP_PERCENTAGE = 0.06;

    private unowned Canberra.Context? ca_context = null;

    /* Smooth scrolling support */
    private double total_x_delta = 0;
    private double total_y_delta= 0;

    public static GLib.Settings settings;

    public Indicator () {
        Object (code_name: Wingpanel.Indicator.SOUND);
    }

    static construct {
        settings = new GLib.Settings ("com.github.hcsubser.hybridbar.sound");
    }

    construct {
        var touchpad_settings = new GLib.Settings ("org.gnome.desktop.peripherals.touchpad");
        touchpad_settings.bind ("natural-scroll", this, "natural-scroll-touchpad", SettingsBindFlags.DEFAULT);
        var mouse_settings = new GLib.Settings ("org.gnome.desktop.peripherals.mouse");
        mouse_settings.bind ("natural-scroll", this, "natural-scroll-mouse", SettingsBindFlags.DEFAULT);

        visible = true;

        display_widget = new DisplayWidget ();

        volume_control = new Services.VolumeControlPulse (); /* sub-class of Services.VolumeControl */
        volume_control.notify["volume"].connect (on_volume_change);
        volume_control.notify["mic-volume"].connect (on_mic_volume_change);
        volume_control.notify["mute"].connect (on_mute_change);
        volume_control.notify["micMute"].connect (on_mic_mute_change);
        volume_control.notify["is-playing"].connect (on_is_playing_change);
        volume_control.notify["is-listening"].connect (update_mic_visibility);

        Notify.init ("wingpanel-indicator-sound");

        settings.notify["max-volume"].connect (set_max_volume);

        var locale = Intl.setlocale (LocaleCategory.MESSAGES, null);

        display_widget.volume_press_event.connect ((e) => {
            if (e.button == Gdk.BUTTON_MIDDLE) {
                volume_control.toggle_mute ();
            }
        });

        display_widget.mic_press_event.connect ((e) => {
            if (e.button == Gdk.BUTTON_MIDDLE) {
                volume_control.toggle_mic_mute ();
            }
        });

        display_widget.icon_name = get_volume_icon (volume_control.volume.volume);

        display_widget.volume_scroll_event.connect_after (on_volume_icon_scroll_event);
        display_widget.mic_scroll_event.connect_after (on_mic_icon_scroll_event);

        volume_scale = new Widgets.Scale ("audio-volume-high-symbolic", true, 0.0, max_volume, 0.01);
        mic_scale = new Widgets.Scale ("audio-input-microphone-symbolic", true, 0.0, 1.0, 0.01);

        ca_context = CanberraGtk.context_get ();
        ca_context.change_props (Canberra.PROP_APPLICATION_NAME, "indicator-sound",
                                 Canberra.PROP_APPLICATION_ID, "wingpanel-indicator-sound",
                                 Canberra.PROP_APPLICATION_NAME, "start-here",
                                 Canberra.PROP_APPLICATION_LANGUAGE, locale,
                                 null);
        ca_context.open ();
    }

    ~Indicator () {
        if (sound_was_blocked_timeout_id > 0) {
            Source.remove (sound_was_blocked_timeout_id);
        }

        if (notify_timeout_id > 0) {
            Source.remove (notify_timeout_id);
        }
    }

    private void set_max_volume () {
        var max = settings.get_double ("max-volume") / 100;
        // we do not allow more than 11db over the NORM volume
        var cap_volume = (double)PulseAudio.Volume.sw_from_dB (11.0) / PulseAudio.Volume.NORM;
        if (max > cap_volume) {
            max = cap_volume;
        }

        max_volume = max;
        on_volume_change ();
    }

    private void on_volume_change () {
        double volume = volume_control.volume.volume / max_volume;
        if (volume != volume_scale.scale_widget.get_value ()) {
            volume_scale.scale_widget.set_value (volume);
            display_widget.icon_name = get_volume_icon (volume);
        }
    }

    private void on_mic_volume_change () {
        var volume = volume_control.mic_volume;

        if (volume != mic_scale.scale_widget.get_value ()) {
            mic_scale.scale_widget.set_value (volume);
        }
    }

    private void on_mute_change () {
        volume_scale.active = !volume_control.mute;

        string volume_icon = get_volume_icon (volume_control.volume.volume);
        display_widget.icon_name = volume_icon;

        if (volume_control.mute) {
            volume_scale.icon = "audio-volume-muted-symbolic";
        } else {
            volume_scale.icon = volume_icon;
        }
    }

    private void on_mic_mute_change () {
        mic_scale.active = !volume_control.micMute;
        display_widget.mic_muted = volume_control.micMute;

        if (volume_control.micMute) {
            mic_scale.icon = "microphone-sensitivity-muted-symbolic";
        } else {
            mic_scale.icon = "audio-input-microphone-symbolic";
        }
    }

    private void on_is_playing_change () {
        if (!volume_control.mute) {
            mute_blocks_sound = false;
            return;
        }
        if (volume_control.is_playing) {
            mute_blocks_sound = true;
        } else if (mute_blocks_sound) {
            /* Continue to show the blocking icon five seconds after a player has tried to play something */
            if (sound_was_blocked_timeout_id > 0) {
                Source.remove (sound_was_blocked_timeout_id);
            }

            sound_was_blocked_timeout_id = Timeout.add_seconds (5, () => {
                mute_blocks_sound = false;
                sound_was_blocked_timeout_id = 0;
                display_widget.icon_name = get_volume_icon (volume_control.volume.volume);
                return false;
            });
        }

        display_widget.icon_name = get_volume_icon (volume_control.volume.volume);
    }

    private void on_volume_icon_scroll_event (Gdk.EventScroll e) {
        double dir = 0.0;
        if (handle_scroll_event (e, out dir)) {
            handle_change (dir, false);
        }
    }

    private void on_mic_icon_scroll_event (Gdk.EventScroll e) {
        double dir = 0.0;
        if (handle_scroll_event (e, out dir)) {
            handle_change (dir, true);
        }
    }

    private void update_mic_visibility () {
        if (volume_control.is_listening) {
            mic_scale.no_show_all = false;
            mic_scale.show_all ();
            mic_separator.no_show_all = false;
            mic_separator.show ();
            display_widget.show_mic = true;
        } else {
            mic_scale.no_show_all = true;
            mic_scale.hide ();
            mic_separator.no_show_all = true;
            mic_separator.hide ();
            display_widget.show_mic = false;
        }
    }

    private unowned string get_volume_icon (double volume) {
        if (volume <= 0 || this.volume_control.mute) {
            return this.mute_blocks_sound ? "audio-volume-muted-blocking-symbolic" : "audio-volume-muted-symbolic";
        } else if (volume <= 0.3) {
            return "audio-volume-low-symbolic";
        } else if (volume <= 0.7) {
            return "audio-volume-medium-symbolic";
        } else {
            return "audio-volume-high-symbolic";
        }
    }

    private void on_volume_switch_change () {
        if (volume_scale.active) {
            volume_control.set_mute (false);
        } else {
            volume_control.set_mute (true);
        }
    }

    private void on_mic_switch_change () {
        if (mic_scale.active) {
            volume_control.set_mic_mute (false);
        } else {
            volume_control.set_mic_mute (true);
        }
    }

    public override Gtk.Widget get_display_widget () {
        return display_widget;
    }


    public override Gtk.Widget? get_widget () {
        if (main_grid == null) {
            int position = 0;
            main_grid = new Gtk.Grid ();

            mpris = new Widgets.MprisWidget ();

            mpris.close.connect (() => {
                close ();
            });
            volume_control.notify["headphone-plugged"].connect (() => {
                if (!volume_control.headphone_plugged)
                    mpris.pause_all ();
            });

            main_grid.attach (mpris, 0, position++, 1, 1);

            if (mpris.get_children ().length () > 0) {
                var first_separator = new Wingpanel.Widgets.Separator ();

                main_grid.attach (first_separator, 0, position++, 1, 1);
            }

            volume_scale.margin_start = 6;
            volume_scale.active = !volume_control.mute;
            volume_scale.notify["active"].connect (on_volume_switch_change);

            volume_scale.scale_widget.value_changed.connect (() => {
                var vol = new Services.VolumeControl.Volume ();
                var v = volume_scale.scale_widget.get_value () * max_volume;
                vol.volume = v.clamp (0.0, max_volume);
                vol.reason = Services.VolumeControl.VolumeReasons.USER_KEYPRESS;
                volume_control.volume = vol;
                volume_scale.icon = get_volume_icon (volume_scale.scale_widget.get_value ());
            });

            volume_scale.scale_widget.set_value (volume_control.volume.volume);
            volume_scale.scale_widget.button_release_event.connect ((e) => {
                notify_change (false);
                return false;
            });


            volume_scale.scroll_event.connect_after ((e) => {
                double dir = 0.0;
                if (handle_scroll_event (e, out dir)) {
                    handle_change (dir, false);
                }

                return true;
            });

            volume_scale.icon = get_volume_icon (volume_scale.scale_widget.get_value ());
            set_max_volume ();

            main_grid.attach (volume_scale, 0, position++, 1, 1);
            main_grid.attach (new Wingpanel.Widgets.Separator (), 0, position++, 1, 1);

            mic_scale.margin_start = 6;
            mic_scale.active = !volume_control.micMute;
            mic_scale.notify["active"].connect (on_mic_switch_change);

            mic_scale.scale_widget.value_changed.connect (() => {
                volume_control.mic_volume = mic_scale.scale_widget.get_value ();
            });

            mic_scale.scale_widget.button_release_event.connect (() => {
                notify_change (true);
                return false;
            });

            mic_scale.scroll_event.connect_after ((e) => {
                double dir = 0.0;
                if (handle_scroll_event (e, out dir)) {
                    handle_change (dir, true);
                }

                return true;
            });


            main_grid.attach (mic_scale, 0, position++, 1, 1);

            mic_separator = new Wingpanel.Widgets.Separator ();

            update_mic_visibility ();

            main_grid.attach (mic_separator, 0, position++, 1, 1);

            var settings_button = new Gtk.ModelButton ();
            settings_button.text = _("Sound Settings…");
            settings_button.clicked.connect (() => {
                show_settings ();
            });

            main_grid.attach (settings_button, 0, position++, 1, 1);
        }

        return main_grid;
    }

    /* Handles both SMOOTH and non-SMOOTH events.
     * In order to deliver smooth volume changes it:
     * * accumulates very small changes until they become significant.
     * * ignores rapid changes in direction.
     * * responds to both horizontal and vertical scrolling.
     * In the case of diagonal scrolling, it ignores the event unless movement in one direction
     * is more than twice the movement in the other direction.
     */
    private bool handle_scroll_event (Gdk.EventScroll e, out double dir) {
        dir = 0.0;
        bool natural_scroll;
        var event_source = e.get_source_device ().input_source;
        if (event_source == Gdk.InputSource.MOUSE) {
            natural_scroll = natural_scroll_mouse;
        } else if (event_source == Gdk.InputSource.TOUCHPAD) {
            natural_scroll = natural_scroll_touchpad;
        } else {
            natural_scroll = false;
        }

        switch (e.direction) {
            case Gdk.ScrollDirection.SMOOTH:
                    var abs_x = double.max (e.delta_x.abs (), 0.0001);
                    var abs_y = double.max (e.delta_y.abs (), 0.0001);

                    if (abs_y / abs_x > 2.0) {
                        total_y_delta += e.delta_y;
                    } else if (abs_x / abs_y > 2.0) {
                        total_x_delta += e.delta_x;
                    }

                break;

            case Gdk.ScrollDirection.UP:
                total_y_delta = -1.0;
                break;
            case Gdk.ScrollDirection.DOWN:
                total_y_delta = 1.0;
                break;
            case Gdk.ScrollDirection.LEFT:
                total_x_delta = -1.0;
                break;
            case Gdk.ScrollDirection.RIGHT:
                total_x_delta = 1.0;
                break;
            default:
                break;
        }

        if (total_y_delta.abs () > 0.5) {
            dir = natural_scroll ? total_y_delta : -total_y_delta;
        } else if (total_x_delta.abs () > 0.5) {
            dir = natural_scroll ? -total_x_delta : total_x_delta;
        }

        if (dir.abs () > 0.0) {
            total_y_delta = 0.0;
            total_x_delta = 0.0;
            return true;
        }

        return false;
    }

    private void handle_change (double change, bool is_mic) {
        double v;

        if (is_mic) {
            v = volume_control.mic_volume;
        } else {
            v = volume_control.volume.volume;
        }

        var new_v = (v + VOLUME_STEP_PERCENTAGE * change).clamp (0.0, max_volume);

        if (new_v == v) {
            /* Ignore if no volume change will result */
            return;
        }

        if (is_mic) {
            volume_control.mic_volume = new_v;
        } else {
            var vol = new Services.VolumeControl.Volume ();
            vol.reason = Services.VolumeControl.VolumeReasons.USER_KEYPRESS;
            vol.volume = new_v;
            volume_control.volume = vol;
        }

        notify_change (is_mic);
    }

    public override void opened () {
        open = true;

        mpris.update_default_player ();

        if (notification != null) {
            try {
                notification.close ();
            } catch (Error e) {
                warning ("Unable to close sound notification: %s", e.message);
            }

            notification = null;
        }
    }

    public override void closed () {
        open = false;
        notification = null;
    }

    private void show_settings () {
        close ();
            if ( (Posix.fork() == 0) ) {
            	Posix.setsid();
				Posix.execl("/bin/sh", "/bin/sh", "-c", settings.get_string ("menu-command"),"");
    		}
    }

    uint notify_timeout_id = 0;
    private void notify_change (bool is_mic) {
        if (notify_timeout_id > 0) {
            return;
        }

        notify_timeout_id = Timeout.add (50, () => {
            bool notification_showing = false;
            /* Show notification if not open */
            if (!open) {
                notification_showing = show_notification (is_mic);
            }

            /* If open or no notification shown, just play sound */
            /* TODO: Should this be suppressed if mic is on? */
            if (!notification_showing) {
                Canberra.Proplist props;
                Canberra.Proplist.create (out props);
                props.sets (Canberra.PROP_CANBERRA_CACHE_CONTROL, "volatile");
                props.sets (Canberra.PROP_EVENT_ID, "audio-volume-change");
                ca_context.play_full (0, props);
            }

            notify_timeout_id = 0;
            return false;
        });
    }

    /* This also plays a sound. TODO Is there a way of suppressing this if mic is on? */
    private bool show_notification (bool is_mic) {
        if (notification == null) {
            notification = new Notify.Notification ("indicator-sound", "", "");
            notification.set_hint ("x-canonical-private-synchronous", new Variant.string ("indicator-sound"));
        }

        if (notification != null) {
            string icon;

            if (is_mic) {
                icon = "audio-input-microphone-symbolic";
            } else {
                icon = get_volume_icon (volume_scale.scale_widget.get_value ());
            }

            notification.update ("indicator-sound", "", icon);

            int32 volume;
            if (is_mic) {
                volume = (int32)Math.round (volume_control.mic_volume / max_volume * 100.0);
            } else {
                volume = (int32)Math.round (volume_control.volume.volume / max_volume * 100.0);
            }

            notification.set_hint ("value", new Variant.int32 (volume));

            try {
                notification.show ();
            } catch (Error e) {
                warning ("Unable to show sound notification: %s", e.message);
                notification = null;
                return false;
            }
        } else {
            return false;
        }

        return true;
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    debug ("Activating Sound Indicator");

    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }

    var indicator = new Sound.Indicator ();
    return indicator;
}

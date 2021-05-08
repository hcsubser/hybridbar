/*
 * Copyright (c) 2014 Ikey Doherty <ikey.doherty@gmail.com>
 *               2016-2018 elementary, Inc. (https://elementary.io)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

const int ICON_SIZE = 48;

/**
 * A ClientWidget is simply used to control and display information in a two-way
 * fashion with an underlying MPRIS provider (MediaPlayer2)
 * It is "designed" to be self contained and added to a large UI, enabling multiple
 * MPRIS clients to be controlled with multiple widgets
 */
public class Sound.Widgets.ClientWidget : Gtk.Grid {
    private const string NOT_PLAYING = _("Not currently playing");

    public signal void close ();

    private Gtk.Image? background = null;
    private Gtk.Image mask;
    private Gtk.Label title_label;
    private Gtk.Label artist_label;
    private Gtk.Button prev_btn;
    private Gtk.Button play_btn;
    private Gtk.Button next_btn;
    private Icon app_icon;
    private Cancellable load_remote_art_cancel;

    private bool launched_by_indicator = false;
    private string app_name = _("Music player");
    private string last_art_url;

    public string mpris_name = "";

    private AppInfo? ainfo;

    public AppInfo? app_info {
        get {
            return ainfo;
        } set {
            ainfo = value;
            if (ainfo != null) {
                app_name = ainfo.get_display_name ();
                if (app_name == "") {
                    app_name = ainfo.get_name ();
                }
                var icon = value.get_icon ();
                if (icon != null) {
                    app_icon = icon;
                    background.set_from_gicon (app_icon, Gtk.IconSize.DIALOG);
                }
            }
        }
    }

    private Services.MprisClient? client_ = null;
    private Services.MediaPlayer? mp_client = null;

    public Services.MprisClient? client {
        get {
            return client_;
        } set {
            this.client_ = value;
            if (value != null) {
                string? desktop_entry = client.player.desktop_entry;
                if (desktop_entry != null && desktop_entry != "") {
                    app_info = new DesktopAppInfo ("%s.desktop".printf (desktop_entry));
                }

                connect_to_client ();
                update_play_status ();
                update_from_meta ();
                update_controls ();

                if (launched_by_indicator) {
                    Idle.add (() => {
                        try {
                            launched_by_indicator = false;
                            client.player.play_pause ();
                        } catch (Error e) {
                            warning ("Could not play/pause: %s", e.message);
                        }

                        return false;
                    });
                }
            } else {
                ((Gtk.Image) play_btn.image).icon_name = "media-playback-start-symbolic";
                prev_btn.sensitive = false;
                next_btn.sensitive = false;
                Sound.Indicator.settings.set_strv (
                    "last-title-info",
                    {
                        app_info.get_id (),
                        title_label.get_text (),
                        artist_label.get_text (),
                        last_art_url
                    }
                );
                this.mpris_name = "";
            }
        }
    }

    /**
     * Create a new ClientWidget
     *
     * @param client The underlying MprisClient instance to use
     */
    public ClientWidget (Services.MprisClient mpris_client) {
        Object (client: mpris_client);
    }

    /**
     * Create a new ClientWidget for bluetooth controls
     *
     * @param client The underlying MediaPlayer instance to use
     */
    public ClientWidget.bluetooth (Services.MediaPlayer media_player_client, string name, string icon) {
        mp_client = media_player_client;

        app_icon = new ThemedIcon (icon);
        background.set_from_gicon (app_icon, Gtk.IconSize.DIALOG);
        title_label.label = name;
        artist_label.label = NOT_PLAYING;

        update_controls ();
    }

    /**
     * Create a new ClientWidget for the default player
     *
     * @param info The AppInfo of the default music player
     */
    public ClientWidget.default (AppInfo info) {
        Object (
            app_info: info,
            client: null
        );

        var title_info = Sound.Indicator.settings.get_strv ("last-title-info");
        if (title_info.length == 4) {
            if (title_info[0] == app_info.get_id ()) {
                title_label.label = title_info[1];
                artist_label.label = title_info[2];
                if (title_info[3] != "") {
                    update_art (title_info[3]);
                }

                return;
            }
        }

        title_label.label = app_name;
        artist_label.label = NOT_PLAYING;
    }

    construct {
        app_icon = new ThemedIcon ("multimedia-audio-player");

        load_remote_art_cancel = new Cancellable ();

        var scale_factor = get_scale_factor ();
        background = new Gtk.Image ();
        background.pixel_size = ICON_SIZE / scale_factor;

        mask = new Gtk.Image.from_resource ("/io/elementary/wingpanel/sound/image-mask.svg");
        mask.no_show_all = true;
        mask.pixel_size = 48 / scale_factor;

        var overlay = new Gtk.Overlay ();
        overlay.can_focus = true;
        overlay.margin_bottom = 2 / scale_factor;
        overlay.margin_end = 4 / scale_factor;
        overlay.margin_start = 4 / scale_factor;
        overlay.add (background);
        overlay.add_overlay (mask);

        var markup_attribute = new Pango.AttrList ();
        markup_attribute.insert (Pango.attr_weight_new (Pango.Weight.BOLD));

        title_label = new Gtk.Label (null);
        title_label.attributes = markup_attribute;
        title_label.ellipsize = Pango.EllipsizeMode.END;
        title_label.max_width_chars = 20;
        title_label.use_markup = false;
        title_label.valign = Gtk.Align.END;
        title_label.xalign = 0;

        artist_label = new Gtk.Label (null);
        artist_label.ellipsize = Pango.EllipsizeMode.END;
        artist_label.max_width_chars = 20;
        artist_label.use_markup = false;
        artist_label.valign = Gtk.Align.START;
        artist_label.xalign = 0;

        var titles = new Gtk.Grid ();
        titles.column_spacing = 3;
        titles.attach (overlay, 0, 0, 1, 2);
        titles.attach (title_label, 1, 0);
        titles.attach (artist_label, 1, 1);

        var titles_events = new Gtk.EventBox ();
        titles_events.hexpand = true;
        titles_events.add (titles);

        prev_btn = new Gtk.Button.from_icon_name (
            "media-skip-backward-symbolic",
            Gtk.IconSize.LARGE_TOOLBAR
        );
        prev_btn.sensitive = false;
        prev_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);

        play_btn = new Gtk.Button.from_icon_name (
            "media-playback-start-symbolic",
            Gtk.IconSize.LARGE_TOOLBAR
        );
        play_btn.sensitive = true;
        play_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);

        next_btn = new Gtk.Button.from_icon_name (
            "media-skip-forward-symbolic",
            Gtk.IconSize.LARGE_TOOLBAR
        );
        next_btn.sensitive = false;
        next_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);

        margin_end = 6 / scale_factor;
        add (titles_events);
        add (prev_btn);
        add (play_btn);
        add (next_btn);

        if (client != null) {
            connect_to_client ();
            update_play_status ();
            update_from_meta ();
            update_controls ();
        }

        titles_events.button_press_event.connect (raise_player);

        prev_btn.clicked.connect (() => {
            Idle.add (() => {
                if (!Thread.supported ()) {
                    warning ("Threading is not supported. DBus timeout could be blocking UI");
                    try {
                        if (mp_client == null && client.player.can_go_previous) {
                            client.player.previous ();
                        } else if (mp_client != null) {
                            mp_client.previous ();
                        }
                    } catch (Error e) {
                        warning ("Going to previous track probably failed (faulty MPRIS interface): %s", e.message);
                    }
                } else {
                    new Thread <void*> ("wingpanel_indicator_sound_dbus_backward_thread", () => {
                        try {
                            if (mp_client == null) {
                                client.player.previous ();
                            } else if (mp_client != null) {
                                mp_client.previous ();
                            }
                        } catch (Error e) {
                            warning ("Going to previous track probably failed (faulty MPRIS interface): %s", e.message);
                        }

                        return null;
                    });
                }

                return false;
            });
        });

        play_btn.clicked.connect (() => {
            Idle.add (() => {
                if (!Thread.supported ()) {
                    warning ("Threading is not supported. DBus timeout could be blocking UI");
                    try {
                        if (mp_client == null) {
                            client.player.play_pause ();
                        } else if (mp_client != null) {
                            if (mp_client.status == "playing") {
                                mp_client.pause ();
                            } else {
                                mp_client.play ();
                            }
                            update_play_status ();
                        }
                    } catch (Error e) {
                        warning ("Playing/Pausing probably failed (faulty MPRIS interface): %s", e.message);
                    }
                } else {
                    new Thread <void*> ("wingpanel_indicator_sound_dbus_backward_thread", () => {
                        try {
                            if (mp_client == null) {
                                client.player.play_pause ();
                            } else if (mp_client != null) {
                                if (mp_client.status == "playing") {
                                    mp_client.pause ();
                                } else {
                                    mp_client.play ();
                                }
                                update_play_status ();
                            }
                        } catch (Error e) {
                            warning ("Playing/Pausing probably failed (faulty MPRIS interface): %s", e.message);
                        }

                        return null;
                    });
                }

                return false;
            });
        });

        next_btn.clicked.connect (() => {
            Idle.add (() => {
                if (!Thread.supported ()) {
                    warning ("Threading is not supported. DBus timeout could be blocking UI");
                    try {
                        if (mp_client == null && client.player.can_go_next) {
                            client.player.next ();
                        } else if (mp_client != null) {
                            mp_client.next ();
                        }
                    } catch (Error e) {
                        warning ("Going to next track probably failed (faulty MPRIS interface): %s", e.message);
                    }
                } else {
                    new Thread <void*> ("wingpanel_indicator_sound_dbus_forward_thread", () => {
                        try {
                            if (mp_client == null) {
                                client.player.next ();
                            } else if (mp_client != null) {
                                mp_client.next ();
                            }
                        } catch (Error e) {
                            warning ("Going to next track probably failed (faulty MPRIS interface): %s", e.message);
                        }

                        return null;
                    });
                }

                return false;
            });
        });
    }

    private void connect_to_client () {
        client.prop.properties_changed.connect ((i, p, inv) => {
            if (i == "org.mpris.MediaPlayer2.Player") {
                /* Handle mediaplayer2 iface */
                p.foreach ((k, v) => {
                    if (k == "Metadata") {
                        Idle.add (() => {
                            update_from_meta ();
                            return false;
                        });
                    } else if (k == "PlaybackStatus") {
                        Idle.add (() => {
                            update_play_status ();
                            return false;
                        });
                    } else if (k == "CanGoNext" || k == "CanGoPrevious") {
                        Idle.add (() => {
                            update_controls ();
                            return false;
                        });
                    }
                });
            }
        });
    }

    private bool raise_player (Gdk.EventButton event) {
        try {
            close ();
            if (client != null && client.player.can_raise) {
                if (!Thread.supported ()) {
                    warning ("Threading is not supported. DBus timeout could be blocking UI");
                    try {
                        client.player.raise ();
                    } catch (Error e) {
                        warning ("Raising the player probably failed (faulty MPRIS interface): %s", e.message);
                    }
                } else {
                    new Thread <void*> ("wingpanel_indicator_sound_dbus_backward_thread", () => {
                        try {
                            client.player.raise ();
                        } catch (Error e) {
                            warning ("Raising the player probably failed (faulty MPRIS interface): %s", e.message);
                        }
                        return null;
                      });
                }
            } else if (app_info != null) {
                app_info.launch (null, null);
            }
        } catch (Error e) {
            warning ("Could not launch player");
        }

        return Gdk.EVENT_STOP;
    }

    /**
     * Update play status based on player requirements
     */
    private void update_play_status () {
        if (client.player.playback_status == "Playing") {
            ((Gtk.Image) play_btn.image).icon_name = "media-playback-pause-symbolic";
        } else {
            ((Gtk.Image) play_btn.image).icon_name = "media-playback-start-symbolic";
        }
    }

    /**
     * Update prev/next sensitivity based on player requirements
     */
    private void update_controls () {
        if (mp_client == null) {
            prev_btn.sensitive = client.player.can_go_previous;
            next_btn.sensitive = client.player.can_go_next;
        } else {
            prev_btn.sensitive = true;
            next_btn.sensitive = true;
        }
    }

    /**
     * Utility, handle updating the album art
     */
    private void update_art (string uri) {
        var scale = get_style_context ().get_scale ();
        if (!uri.has_prefix ("file://") && !uri.has_prefix ("http")) {
            background.gicon = app_icon;
            background.get_style_context ().set_scale (scale);
            mask.no_show_all = true;
            mask.hide ();
            return;
        }

        if (uri.has_prefix ("file://")) {
            string fname = uri.split ("file://")[1];
            try {
                var pbuf = new Gdk.Pixbuf.from_file_at_size (fname, ICON_SIZE * scale, ICON_SIZE * scale);
                background.gicon = mask_pixbuf (pbuf, scale);
                background.get_style_context ().set_scale (1);
                mask.no_show_all = false;
                mask.show ();
            } catch (Error e) {
                //background.set_from_gicon (app_icon, Gtk.IconSize.DIALOG);
            }
        } else {
            load_remote_art_cancel.cancel ();
            load_remote_art_cancel.reset ();
            load_remote_art.begin (uri);
        }
    }

    private async void load_remote_art (string uri) {
        var scale = get_style_context ().get_scale ();
        GLib.File file = GLib.File.new_for_uri (uri);
        try {
            GLib.InputStream stream = yield file.read_async (Priority.DEFAULT, load_remote_art_cancel);
            Gdk.Pixbuf pixbuf = yield new Gdk.Pixbuf.from_stream_async (stream, load_remote_art_cancel);
            if (pixbuf != null) {
                background.gicon = mask_pixbuf (pixbuf, scale);
                background.get_style_context ().set_scale (1);
                mask.no_show_all = false;
                mask.show ();
            }
        } catch (Error e) {
            background.gicon = app_icon;
            background.get_style_context ().set_scale (scale);
            mask.no_show_all = true;
            mask.hide ();
        }
    }

    /**
     * Update display info such as artist, the background image, etc.
     */
    protected void update_from_meta () {
        var metadata = client.player.metadata;
        if ("mpris:artUrl" in metadata) {
            var url = metadata["mpris:artUrl"].get_string ();
            if (url != last_art_url) {
                update_art (url);
                last_art_url = url;
            }
        } else {
            last_art_url = "";
            background.pixel_size = ICON_SIZE;
            background.set_from_gicon (app_icon, Gtk.IconSize.DIALOG);
            mask.no_show_all = true;
            mask.hide ();
        }

        string title;
        if ("xesam:title" in metadata && metadata["xesam:title"].is_of_type (VariantType.STRING)
            && metadata["xesam:title"].get_string () != "") {
            title = metadata["xesam:title"].get_string ();
        } else {
            title = app_name;
        }

        title_label.label = title;

        if ("xesam:artist" in metadata && metadata["xesam:artist"].is_of_type (VariantType.STRING_ARRAY)) {
            (unowned string)[] artists = metadata["xesam:artist"].get_strv ();
            artist_label.label = string.joinv (", ", artists);
        } else {
            if (client.player.playback_status == "Playing") {
                artist_label.label = _("Unknown Artist");
            } else {
                artist_label.label = NOT_PLAYING;
            }
        }
    }

    private static Gdk.Pixbuf? mask_pixbuf (Gdk.Pixbuf pixbuf, int scale) {
        var size = ICON_SIZE * scale;
        var mask_offset = 4 * scale;
        var mask_size_offset = mask_offset * 2;
        var mask_size = ICON_SIZE * scale;
        var offset_x = mask_offset;
        var offset_y = mask_offset + scale;
        size = size - mask_size_offset;

        var input = pixbuf.scale_simple (size, size, Gdk.InterpType.BILINEAR);
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, mask_size, mask_size);
        var cr = new Cairo.Context (surface);

        //Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, offset_x, offset_y, size, size, mask_offset);
        cr.clip ();

        Gdk.cairo_set_source_pixbuf (cr, input, offset_x, offset_y);
        cr.paint ();

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, mask_size, mask_size);
    }

    public void update_play (string playing, string title, string artist) {
        if (playing != "") {
            switch (playing) {
                case "playing":
                    ((Gtk.Image)play_btn.image).set_from_icon_name (
                        "media-playback-pause-symbolic",
                        Gtk.IconSize.LARGE_TOOLBAR
                    );
                    break;
                default:
                    /* Stopped, Paused */
                    ((Gtk.Image)play_btn.image).set_from_icon_name (
                        "media-playback-start-symbolic",
                        Gtk.IconSize.LARGE_TOOLBAR
                    );
                    break;
            }
        }

        if (title != "" && artist != "") {
            title_label.label = title;
            artist_label.label = artist;
        }
    }
}

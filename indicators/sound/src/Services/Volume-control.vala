/*
 * -*- Mode:Vala; indent-tabs-mode:t; tab-width:4; encoding:utf8 -*-
 * Copyright (c) 2013 Canonical Ltd.
 *               2015-2017 elementary LLC. (http://launchpad.net/wingpanel)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *      Alberto Ruiz <alberto.ruiz@canonical.com>
 *      Ted Gould <ted@canonical.com>
 */

 public abstract class Sound.Services.VolumeControl : Object {
    public enum VolumeReasons {
        PULSE_CHANGE,
        ACCOUNTS_SERVICE_SET,
        DEVICE_OUTPUT_CHANGE,
        USER_KEYPRESS,
        VOLUME_STREAM_CHANGE
    }

    public class Volume : Object {
        public double volume;
        public VolumeReasons reason;
    }

    public virtual string stream { get { return ""; } }
    public virtual bool ready { get { return false; } set { } }
    public virtual bool active_mic { get { return false; } set { } }
    public virtual bool high_volume { get { return false; } }
    public virtual bool mute { get { return false; } }
    public virtual bool mic_mute { get { return false; } }
    public virtual bool is_playing { get { return false; } }
    public virtual bool is_listening { get { return false; } }
    private Volume _volume;
    public virtual Volume volume { get { return _volume; } set { } }
    public virtual double mic_volume { get { return 0.0; } set { } }
    public bool headphone_plugged { get; protected set; default = false; }

    public abstract void set_mute (bool mute);
}

[CCode (cname="pa_cvolume_set", cheader_filename = "pulse/volume.h")]
extern unowned PulseAudio.CVolume? vol_set (PulseAudio.CVolume? cv, uint channels, PulseAudio.Volume v);

public class Sound.Services.VolumeControlPulse : VolumeControl {
    /* this is static to ensure it being freed after @context (loop does not have ref counting) */
    private static PulseAudio.GLibMainLoop loop;

    private uint _reconnect_timer = 0;

    private PulseAudio.Context context;
    private bool _mute = true;
    private bool _mute_mic = true;
    private bool _is_playing = false;
    private bool _is_listening = false;
    private VolumeControl.Volume _volume = new VolumeControl.Volume ();
    private double _mic_volume = 0.0;

    /* Used by the pulseaudio stream restore extension */
    // private DBusConnection _pconn;
    /* Need both the list and hash so we can retrieve the last known sink-input after
     * releasing the current active one (restoring back to the previous known role) */
    private Gee.ArrayList<uint32> _sink_input_list = new Gee.ArrayList<uint32> ();
    private Gee.HashMap<uint32, string> _sink_input_hash = new Gee.HashMap<uint32, string> ();
    private bool _pulse_use_stream_restore = false;
    private int32 _active_sink_input = -1;
    private string[] _valid_roles = {"multimedia", "alert", "alarm", "phone"};
    public override string stream {
        get {
            if (_active_sink_input == -1)
                return "alert";
            var path = _sink_input_hash[_active_sink_input];
            if (path == _objp_role_multimedia)
                return "multimedia";
            if (path == _objp_role_alert)
                return "alert";
            if (path == _objp_role_alarm)
                return "alarm";
            if (path == _objp_role_phone)
                return "phone";
            return "alert";
        }
    }
    private string? _objp_role_multimedia = null;
    private string? _objp_role_alert = null;
    private string? _objp_role_alarm = null;
    private string? _objp_role_phone = null;

    private Cancellable _mute_cancellable;
    private Cancellable _volume_cancellable;
    private uint _local_volume_timer = 0;
    private bool _send_next_local_volume = false;

    /** true when connected to the pulse server */
    public override bool ready { get; set; }

    /** true when a microphone is active **/
    public override bool active_mic { get; set; default = false; }

    /** true when high volume warnings should be shown */
    public override bool high_volume {
        get {
            return this._volume.volume > 0.75 && headphone_plugged && stream == "multimedia";
        }
    }

    public VolumeControlPulse () {
        _volume.volume = 0.0;
        _volume.reason = VolumeControl.VolumeReasons.PULSE_CHANGE;

        if (loop == null)
            loop = new PulseAudio.GLibMainLoop ();

        _mute_cancellable = new Cancellable ();
        _volume_cancellable = new Cancellable ();

        reconnect_to_pulse.begin ();
    }

    ~VolumeControlPulse () {
        if (_reconnect_timer != 0) {
            Source.remove (_reconnect_timer);
            _reconnect_timer = 0;
        }
        stop_local_volume_timer ();
    }

    /* PulseAudio logic*/
    private void context_events_cb (PulseAudio.Context c, PulseAudio.Context.SubscriptionEventType t, uint32 index) {
        switch (t & PulseAudio.Context.SubscriptionEventType.FACILITY_MASK) {
            case PulseAudio.Context.SubscriptionEventType.SINK:
                update_sink ();
                break;

            case PulseAudio.Context.SubscriptionEventType.SINK_INPUT:
                switch (t & PulseAudio.Context.SubscriptionEventType.TYPE_MASK) {
                    case PulseAudio.Context.SubscriptionEventType.NEW:
                        c.get_sink_input_info (index, handle_new_sink_input_cb);
                        break;

                    case PulseAudio.Context.SubscriptionEventType.CHANGE:
                        c.get_sink_input_info (index, handle_changed_sink_input_cb);
                        break;

                    case PulseAudio.Context.SubscriptionEventType.REMOVE:
                        remove_sink_input_from_list (index);
                        break;
                    default:
                        debug ("Sink input event not known.");
                        break;
                }
                break;

            case PulseAudio.Context.SubscriptionEventType.SOURCE:
                update_source ();
                break;

            case PulseAudio.Context.SubscriptionEventType.SOURCE_OUTPUT:
                switch (t & PulseAudio.Context.SubscriptionEventType.TYPE_MASK) {
                    case PulseAudio.Context.SubscriptionEventType.NEW:
                        c.get_source_output_info (index, source_output_info_cb);
                        break;

                    case PulseAudio.Context.SubscriptionEventType.REMOVE:
                        this.active_mic = false;
                        break;
                }
                break;
        }
    }

    private void sink_info_cb_for_props (PulseAudio.Context c, PulseAudio.SinkInfo? i, int eol) {
        if (i == null)
            return;

        if (_mute != (bool)i.mute) {
            _mute = (bool)i.mute;
            this.notify_property ("mute");
        }

        var playing = (i.state == PulseAudio.SinkState.RUNNING);
        if (_is_playing != playing) {
            _is_playing = playing;
            this.notify_property ("is-playing");
        }

        /* Check if the current active port is headset/headphone */
        /* There is not easy way to check if the port is a headset/headphone besides
         * checking for the port name. On touch (with the pulseaudio droid element)
         * the headset/headphone port is called 'output-headset' and 'output-headphone'.
         * On the desktop this is usually called 'analog-output-headphones' */
        if (i.active_port != null &&
            (i.active_port.name == "output-wired_headset" ||
             i.active_port.name == "output-wired_headphone" ||
             i.active_port.name == "analog-output-headphones")) {
            if (!headphone_plugged) {
                headphone_plugged = true;
                debug ("headphone plugged in\n");
            }
        } else {
            if (headphone_plugged) {
                headphone_plugged = false;
                debug ("no headphone plugged in\n");
            }
        }

        if (_pulse_use_stream_restore == false &&
                _volume.volume != volume_to_double (i.volume.max ())) {
            var vol = new VolumeControl.Volume ();
            vol.volume = volume_to_double (i.volume.max ());
            vol.reason = VolumeControl.VolumeReasons.PULSE_CHANGE;
            this.volume = vol;
        }
    }

    private void source_info_cb (PulseAudio.Context c, PulseAudio.SourceInfo? i, int eol) {
        if (i == null)
            return;

        if (_mute_mic != (bool)i.mute) {
            _mute_mic = (bool)i.mute;
            this.notify_property ("micMute");
        }

        var listening = (i.state == PulseAudio.SourceState.RUNNING);
        if (_is_listening != listening) {
            _is_listening = listening;
            this.notify_property ("is-listening");
        }

        if (_mic_volume != volume_to_double (i.volume.values[0])) {
            _mic_volume = volume_to_double (i.volume.values[0]);
            this.notify_property ("mic-volume");
        }
    }

    private void server_info_cb_for_props (PulseAudio.Context c, PulseAudio.ServerInfo? i) {
        if (i == null)
            return;
        context.get_sink_info_by_name (i.default_sink_name, sink_info_cb_for_props);
    }

    private void update_sink () {
        context.get_server_info (server_info_cb_for_props);
    }

    private void update_source_get_server_info_cb (PulseAudio.Context c, PulseAudio.ServerInfo? i) {
        if (i != null)
            context.get_source_info_by_name (i.default_source_name, source_info_cb);
    }

    private void update_source () {
        context.get_server_info (update_source_get_server_info_cb);
    }

    // private DBusMessage pulse_dbus_filter (DBusConnection connection, owned DBusMessage message, bool incoming) {
    //     if (message.get_message_type () == DBusMessageType.SIGNAL) {
    //         string active_role_objp = _objp_role_alert;
    //         if (_active_sink_input != -1)
    //             active_role_objp = _sink_input_hash.get (_active_sink_input);

    //         if (message.get_path () == active_role_objp && message.get_member () == "VolumeUpdated") {
    //             uint sig_count = 0;
    //             lock (_pa_volume_sig_count) {
    //                 sig_count = _pa_volume_sig_count;
    //                 if (_pa_volume_sig_count > 0)
    //                     _pa_volume_sig_count--;
    //             }

    //             /* We only care about signals if our internal count is zero */
    //             if (sig_count == 0) {
    //                 /* Extract volume and make sure it's not a side effect of us setting it */
    //                 Variant body = message.get_body ();
    //                 Variant varray = body.get_child_value (0);

    //                 uint32 type = 0, lvolume = 0;
    //                 VariantIter iter = varray.iterator ();
    //                 iter.next ("(uu)", &type, &lvolume);
    //                 /* Here we need to compare integer values to avoid rounding issues, so just
    //                  * using the volume values used by pulseaudio */
    //                 PulseAudio.Volume cvolume = double_to_volume (_volume.volume);
    //                 if (lvolume != cvolume) {
    //                     /* Someone else changed the volume for this role, reflect on the indicator */
    //                     var vol = new VolumeControl.Volume();
    //                     vol.volume = volume_to_double (lvolume);
    //                     vol.reason = VolumeControl.VolumeReasons.PULSE_CHANGE;
    //                     this.volume = vol;
    //                 }
    //             }
    //         }
    //     }

    //     return message;
    // }

    // private async void update_active_sink_input (int32 index) {
    //     if ((index == -1) || (index != _active_sink_input && index in _sink_input_list)) {
    //         string sink_input_objp = _objp_role_alert;
    //         if (index != -1)
    //             sink_input_objp = _sink_input_hash.get (index);
    //         _active_sink_input = index;

    //         /* Listen for role volume changes from pulse itself (external clients) */
    //         try {
    //             var builder = new VariantBuilder (new VariantType ("ao"));
    //             builder.add ("o", sink_input_objp);

    //             yield _pconn.call ("org.PulseAudio.Core1", "/org/pulseaudio/core1",
    //                     "org.PulseAudio.Core1", "ListenForSignal",
    //                     new Variant ("(sao)", "org.PulseAudio.Ext.StreamRestore1.RestoreEntry.VolumeUpdated", builder),
    //                     null, DBusCallFlags.NONE, -1);
    //         } catch (GLib.Error e) {
    //             warning ("unable to listen for pulseaudio dbus signals (%s)", e.message);
    //         }

    //         try {
    //             var props_variant = yield _pconn.call ("org.PulseAudio.Ext.StreamRestore1.RestoreEntry",
    //                     sink_input_objp, "org.freedesktop.DBus.Properties", "Get",
    //                     new Variant ("(ss)", "org.PulseAudio.Ext.StreamRestore1.RestoreEntry", "Volume"),
    //                     null, DBusCallFlags.NONE, -1);
    //             Variant tmp;
    //             props_variant.get ("(v)", out tmp);
    //             uint32 type = 0, volume = 0;
    //             VariantIter iter = tmp.iterator ();
    //             iter.next ("(uu)", &type, &volume);

    //             var vol = new VolumeControl.Volume();
    //             vol.volume = volume_to_double (volume);
    //             vol.reason = VolumeControl.VolumeReasons.VOLUME_STREAM_CHANGE;
    //             this.volume = vol;
    //         } catch (GLib.Error e) {
    //             warning ("unable to get volume for active role %s (%s)", sink_input_objp, e.message);
    //         }
    //     }
    // }

    private void add_sink_input_into_list (PulseAudio.SinkInputInfo sink_input) {
        /* We're only adding ones that are not corked and with a valid role */
        var role = sink_input.proplist.gets (PulseAudio.Proplist.PROP_MEDIA_ROLE);

        if (role != null && role in _valid_roles) {
            if (role == "phone") { //sink_input.corked == 0 || role == "phone") {
                _sink_input_list.insert (0, sink_input.index);
                switch (role) {
                    case "multimedia":
                        _sink_input_hash.set (sink_input.index, _objp_role_multimedia);
                        break;
                    case "alert":
                        _sink_input_hash.set (sink_input.index, _objp_role_alert);
                        break;
                    case "alarm":
                        _sink_input_hash.set (sink_input.index, _objp_role_alarm);
                        break;
                    case "phone":
                        _sink_input_hash.set (sink_input.index, _objp_role_phone);
                        break;
                }
                /* Only switch the active sink input in case a phone one is not active */
                if (_active_sink_input == -1 || _sink_input_hash.get (_active_sink_input) != _objp_role_phone) {
                    update_active_sink_input.begin ((int32)sink_input.index);
                }
            }
        }
    }

    private void remove_sink_input_from_list (uint32 index) {
        if (index in _sink_input_list) {
            _sink_input_list.remove (index);
            _sink_input_hash.unset (index);
            if (index == _active_sink_input) {
                if (_sink_input_list.size != 0)
                    update_active_sink_input.begin ((int32)_sink_input_list.get (0));
                else
                    update_active_sink_input.begin (-1);
            }
        }
    }

    private void handle_new_sink_input_cb (PulseAudio.Context c, PulseAudio.SinkInputInfo? i, int eol) {
        if (i == null)
            return;

        add_sink_input_into_list (i);
    }

    private void handle_changed_sink_input_cb (PulseAudio.Context c, PulseAudio.SinkInputInfo? i, int eol) {
        if (i == null)
            return;

        if (i.index in _sink_input_list) {
            /* Phone stream is always corked, so handle it differently */
            if (_sink_input_hash.get (i.index) != _objp_role_phone ) //&& i.corked == 1 &&)
                remove_sink_input_from_list (i.index);
        } else {
            // if (i.corked == 0)
                add_sink_input_into_list (i);
        }
    }

    private void source_output_info_cb (PulseAudio.Context c, PulseAudio.SourceOutputInfo? i, int eol) {
        if (i == null)
            return;

        var role = i.proplist.gets (PulseAudio.Proplist.PROP_MEDIA_ROLE);
        if (role == "phone" || role == "production")
            this.active_mic = true;
    }

    private void context_state_callback (PulseAudio.Context c) {
        switch (c.get_state ()) {
            case PulseAudio.Context.State.READY:
                if (_pulse_use_stream_restore) {
                    c.subscribe (PulseAudio.Context.SubscriptionMask.SINK |
                            PulseAudio.Context.SubscriptionMask.SINK_INPUT |
                            PulseAudio.Context.SubscriptionMask.SOURCE |
                            PulseAudio.Context.SubscriptionMask.SOURCE_OUTPUT);
                } else {
                    c.subscribe (PulseAudio.Context.SubscriptionMask.SINK |
                            PulseAudio.Context.SubscriptionMask.SOURCE |
                            PulseAudio.Context.SubscriptionMask.SOURCE_OUTPUT);
                }
                c.set_subscribe_callback (context_events_cb);
                update_sink ();
                update_source ();
                this.ready = true;
                break;

            case PulseAudio.Context.State.FAILED:
            case PulseAudio.Context.State.TERMINATED:
                if (_reconnect_timer == 0)
                    _reconnect_timer = Timeout.add_seconds (2, reconnect_timeout);
                break;

            default:
                this.ready = false;
                break;
        }
    }

    bool reconnect_timeout () {
        _reconnect_timer = 0;
        reconnect_to_pulse.begin ();
        return false; // G_SOURCE_REMOVE
    }

    async void reconnect_to_pulse () {
        if (this.ready) {
            this.context.disconnect ();
            this.context = null;
            this.ready = false;
        }

        var props = new PulseAudio.Proplist ();
        props.sets (PulseAudio.Proplist.PROP_APPLICATION_NAME, "elementary OS Audio Settings");
        props.sets (PulseAudio.Proplist.PROP_APPLICATION_ID, "com.github.hcsubser.hybridbar.sound");
        props.sets (PulseAudio.Proplist.PROP_APPLICATION_ICON_NAME, "multimedia-volume-control");
        props.sets (PulseAudio.Proplist.PROP_APPLICATION_VERSION, "0.1");

        // reconnect_pulse_dbus ();

        this.context = new PulseAudio.Context (loop.get_api (), null, props);
        this.context.set_state_callback (context_state_callback);

        if (context.connect (null, PulseAudio.Context.Flags.NOFAIL, null) < 0)
            warning ("pa_context_connect() failed: %s\n", PulseAudio.strerror (context.errno ()));
    }

    void sink_info_list_callback_set_mute (PulseAudio.Context context, PulseAudio.SinkInfo? sink, int eol) {
        if (sink != null)
            context.set_sink_mute_by_index (sink.index, true, null);
    }

    void sink_info_list_callback_unset_mute (PulseAudio.Context context, PulseAudio.SinkInfo? sink, int eol) {
        if (sink != null)
            context.set_sink_mute_by_index (sink.index, false, null);
    }

    /* Mute operations */
    bool set_mute_internal (bool mute) {
        return_val_if_fail (context.get_state () == PulseAudio.Context.State.READY, false);

        if (_mute != mute) {
            if (mute)
                context.get_sink_info_list (sink_info_list_callback_set_mute);
            else
                context.get_sink_info_list (sink_info_list_callback_unset_mute);
            return true;
        } else {
            return false;
        }
    }

    public override void set_mute (bool mute) {
        set_mute_internal (mute);
    }

    public void toggle_mute () {
        this.set_mute (!this._mute);
    }

    public override bool mute {
        get {
            return this._mute;
        }
    }

    void source_info_list_callback_set_mute (PulseAudio.Context context, PulseAudio.SourceInfo? source, int eol) {
        if (source != null)
            context.set_source_mute_by_index (source.index, true, null);
    }

    void source_info_list_callback_unset_mute (PulseAudio.Context context, PulseAudio.SourceInfo? source, int eol) {
        if (source != null)
            context.set_source_mute_by_index (source.index, false, null);
    }

    /* Mute operations */
    bool set_mic_mute_internal (bool m) {
        return_val_if_fail (context.get_state () == PulseAudio.Context.State.READY, false);

        if (_mute_mic != m) {
            if (m)
                context.get_source_info_list (source_info_list_callback_set_mute);
            else
                context.get_source_info_list (source_info_list_callback_unset_mute);
            return true;
        } else {
            return false;
        }
    }

    public void set_mic_mute (bool m) {
        set_mic_mute_internal (m);
    }

    public void toggle_mic_mute () {
        this.set_mic_mute (!this._mute_mic);
    }

    public bool micMute {
        get {
            return this._mute_mic;
        }
    }

    public override bool is_playing {
        get {
            return this._is_playing;
        }
    }

    public override bool is_listening {
        get {
            return this._is_listening;
        }
    }

    /* Volume operations */
    private static PulseAudio.Volume double_to_volume (double vol) {
        double tmp = (double)(PulseAudio.Volume.NORM - PulseAudio.Volume.MUTED) * vol;
        return (PulseAudio.Volume)tmp + PulseAudio.Volume.MUTED;
    }

    private static double volume_to_double (PulseAudio.Volume vol) {
        double tmp = (double)(vol - PulseAudio.Volume.MUTED);
        return tmp / (double)(PulseAudio.Volume.NORM - PulseAudio.Volume.MUTED);
    }

    private void set_volume_success_cb (PulseAudio.Context c, int success) {
        if ((bool)success)
            this.notify_property ("volume");
    }

    private void sink_info_set_volume_cb (PulseAudio.Context c, PulseAudio.SinkInfo? i, int eol) {
        if (i == null)
            return;

        unowned PulseAudio.CVolume cvol = i.volume;
        cvol.scale (double_to_volume (_volume.volume));
        c.set_sink_volume_by_index (i.index, cvol, set_volume_success_cb);
    }

    private void server_info_cb_for_set_volume (PulseAudio.Context c, PulseAudio.ServerInfo? i) {
        if (i == null) {
            warning ("Could not get PulseAudio server info");
            return;
        }

        context.get_sink_info_by_name (i.default_sink_name, sink_info_set_volume_cb);
    }

    // private async void set_volume_active_role () {
    //     string active_role_objp = _objp_role_alert;

    //     if (_active_sink_input != -1 && _active_sink_input in _sink_input_list)
    //         active_role_objp = _sink_input_hash.get (_active_sink_input);

    //     try {
    //         double vol = _volume.volume;
    //         var builder = new VariantBuilder (new VariantType ("a(uu)"));
    //         builder.add ("(uu)", 0, double_to_volume (vol));
    //         Variant volume = builder.end ();

    //         /* Increase the signal counter so we can handle the callback */
    //         lock (_pa_volume_sig_count) {
    //             _pa_volume_sig_count++;
    //         }

    //         yield _pconn.call ("org.PulseAudio.Ext.StreamRestore1.RestoreEntry",
    //                 active_role_objp, "org.freedesktop.DBus.Properties", "Set",
    //                 new Variant ("(ssv)", "org.PulseAudio.Ext.StreamRestore1.RestoreEntry", "Volume", volume),
    //                 null, DBusCallFlags.NONE, -1);

    //         debug ("Set volume to %f on path %s", vol, active_role_objp);
    //     } catch (GLib.Error e) {
    //         lock (_pa_volume_sig_count) {
    //             _pa_volume_sig_count--;
    //         }
    //         warning ("unable to set volume for stream obj path %s (%s)", active_role_objp, e.message);
    //     }
    // }

    void set_mic_volume_success_cb (PulseAudio.Context c, int success) {
        if ((bool)success)
            this.notify_property ("mic-volume");
    }

    void set_mic_volume_get_server_info_cb (PulseAudio.Context c, PulseAudio.ServerInfo? i) {
        if (i != null) {
            unowned PulseAudio.CVolume cvol = PulseAudio.CVolume ();
            cvol = vol_set (cvol, 1, double_to_volume (_mic_volume));
            c.set_source_volume_by_name (i.default_source_name, cvol, set_mic_volume_success_cb);
        }
    }

    public override VolumeControl.Volume volume {
        get {
            return _volume;
        }
        set {
            var volume_changed = (value.volume != _volume.volume);
            debug ("Setting volume to %f for profile %d because %d", value.volume, _active_sink_input, value.reason);

            var old_high_volume = this.high_volume;
            _volume = value;

            /* Make sure we're connected to Pulse and pulse didn't give us the change */
            if (context.get_state () == PulseAudio.Context.State.READY &&
                    _volume.reason != VolumeControl.VolumeReasons.PULSE_CHANGE &&
                    volume_changed)
                // if (_pulse_use_stream_restore)
                //     set_volume_active_role.begin ();
                // else
                    context.get_server_info (server_info_cb_for_set_volume);

            if (this.high_volume != old_high_volume)
                this.notify_property ("high-volume");

            if (volume.reason != VolumeControl.VolumeReasons.ACCOUNTS_SERVICE_SET
                && volume_changed) {
                start_local_volume_timer ();
            }
        }
    }

    public override double mic_volume {
        get {
            return _mic_volume;
        }
        set {
            return_if_fail (context.get_state () == PulseAudio.Context.State.READY);

            _mic_volume = value;

            context.get_server_info (set_mic_volume_get_server_info_cb);
        }
    }

    // /* PulseAudio Dbus (Stream Restore) logic */
    // private void reconnect_pulse_dbus () {
    //     unowned string pulse_dbus_server_env = Environment.get_variable ("PULSE_DBUS_SERVER");
    //     string address;

    //     /* In case of a reconnect */
    //     _pulse_use_stream_restore = false;
    //     _pa_volume_sig_count = 0;

    //     if (pulse_dbus_server_env != null) {
    //         address = pulse_dbus_server_env;
    //     } else {
    //         DBusConnection conn;
    //         Variant props;

    //         try {
    //             conn = Bus.get_sync (BusType.SESSION);
    //         } catch (GLib.IOError e) {
    //             warning ("unable to get the dbus session bus: %s", e.message);
    //             return;
    //         }

    //         try {
    //             var props_variant = conn.call_sync ("org.PulseAudio1",
    //                     "/org/pulseaudio/server_lookup1", "org.freedesktop.DBus.Properties",
    //                     "Get", new Variant ("(ss)", "org.PulseAudio.ServerLookup1", "Address"),
    //                     null, DBusCallFlags.NONE, -1);
    //             props_variant.get ("(v)", out props);
    //             address = props.get_string ();
    //         } catch (GLib.Error e) {
    //             warning ("unable to get pulse unix socket: %s", e.message);
    //             return;
    //         }
    //     }

    //     debug ("PulseAudio dbus unix socket: %s", address);
    //     try {
    //         _pconn = new DBusConnection.for_address_sync (address, DBusConnectionFlags.AUTHENTICATION_CLIENT);
    //     } catch (GLib.Error e) {
    //         /* If it fails, it means the dbus pulse extension is not available */
    //         return;
    //     }

    //     /* For pulse dbus related events */
    //     _pconn.add_filter (pulse_dbus_filter);

    //      Check if the 4 currently supported media roles are already available in StreamRestore
    //      * Roles: multimedia, alert, alarm and phone
    //     _objp_role_multimedia = stream_restore_get_object_path ("sink-input-by-media-role:multimedia");
    //     _objp_role_alert = stream_restore_get_object_path ("sink-input-by-media-role:alert");
    //     _objp_role_alarm = stream_restore_get_object_path ("sink-input-by-media-role:alarm");
    //     _objp_role_phone = stream_restore_get_object_path ("sink-input-by-media-role:phone");

    //     /* Only use stream restore if every used role is available */
    //     if (_objp_role_multimedia != null && _objp_role_alert != null && _objp_role_alarm != null && _objp_role_phone != null) {
    //         debug ("Using PulseAudio DBUS Stream Restore module");
    //         /* Restore volume and update default entry */
    //         update_active_sink_input.begin (-1);
    //         _pulse_use_stream_restore = true;
    //     }
    // }

    // private string? stream_restore_get_object_path (string name) {
    //     string? objp = null;
    //     try {
    //         Variant props_variant = _pconn.call_sync ("org.PulseAudio.Ext.StreamRestore1",
    //                 "/org/pulseaudio/stream_restore1", "org.PulseAudio.Ext.StreamRestore1",
    //                 "GetEntryByName", new Variant ("(s)", name), null, DBusCallFlags.NONE, -1);
    //         /* Workaround for older versions of vala that don't provide get_objv */
    //         VariantIter iter = props_variant.iterator ();
    //         iter.next ("o", &objp);
    //         debug ("Found obj path %s for restore data named %s\n", objp, name);
    //     } catch (GLib.Error e) {
    //         warning ("unable to find stream restore data for: %s", name);
    //     }
    //     return objp;
    // }

    private async void update_active_sink_input (int32 index) {
            // if ((index == -1) || (index != _active_sink_input && index in _sink_input_list)) {
            //     string sink_input_objp = _objp_role_alert;
            //     if (index != -1)
            //         sink_input_objp = _sink_input_hash.get (index);
            //     _active_sink_input = index;

            //     /* Listen for role volume changes from pulse itself (external clients) */
            //     try {
            //         var builder = new VariantBuilder (new VariantType ("ao"));
            //         builder.add ("o", sink_input_objp);

            //         yield _pconn.call ("org.PulseAudio.Core1", "/org/pulseaudio/core1",
            //                 "org.PulseAudio.Core1", "ListenForSignal",
            //                 new Variant ("(sao)", "org.PulseAudio.Ext.StreamRestore1.RestoreEntry.VolumeUpdated", builder),
            //                 null, DBusCallFlags.NONE, -1);
            //     } catch (GLib.Error e) {
            //         warning ("unable to listen for pulseaudio dbus signals (%s)", e.message);
            //     }

            //     try {
            //         var props_variant = yield _pconn.call ("org.PulseAudio.Ext.StreamRestore1.RestoreEntry",
            //                 sink_input_objp, "org.freedesktop.DBus.Properties", "Get",
            //                 new Variant ("(ss)", "org.PulseAudio.Ext.StreamRestore1.RestoreEntry", "Volume"),
            //                 null, DBusCallFlags.NONE, -1);
            //         Variant tmp;
            //         props_variant.get ("(v)", out tmp);
            //         uint32 type = 0, volume = 0;
            //         VariantIter iter = tmp.iterator ();
            //         iter.next ("(uu)", &type, &volume);

            //         var vol = new VolumeControl.Volume();
            //         vol.volume = volume_to_double (volume);
            //         vol.reason = VolumeControl.VolumeReasons.VOLUME_STREAM_CHANGE;
            //         this.volume = vol;
            //     } catch (GLib.Error e) {
            //         warning ("unable to get volume for active role %s (%s)", sink_input_objp, e.message);
            //     }
            // }
        }

    private void start_local_volume_timer () {
        if (_local_volume_timer == 0) {
            _local_volume_timer = Timeout.add_seconds (1, local_volume_changed_timeout);
        } else {
            _send_next_local_volume = true;
        }
    }

    private void stop_local_volume_timer () {
        if (_local_volume_timer != 0) {
            Source.remove (_local_volume_timer);
            _local_volume_timer = 0;
        }
    }

    bool local_volume_changed_timeout () {
        _local_volume_timer = 0;
        if (_send_next_local_volume) {
            _send_next_local_volume = false;
            start_local_volume_timer ();
        }
        return false; // G_SOURCE_REMOVE
    }
}

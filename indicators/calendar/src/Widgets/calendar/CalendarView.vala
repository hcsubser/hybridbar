/*-
 * Copyright (c) 2011–2018 elementary, Inc. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Maxwell Barvian
 *              Corentin Noël <corentin@elementaryos.org>
 */

public class DateTime.Widgets.CalendarView : Gtk.Grid {
    public signal void day_double_click ();
    public signal void event_updates ();
    public signal void selection_changed (GLib.DateTime? new_date);

    public GLib.DateTime? selected_date { get; private set; }

    private Hdy.Carousel carousel;
    private uint position;
    private int rel_postion;
    private CalendarModel calmodel;
    private GLib.DateTime start_month;
    private DateTime.Widgets.Grid start_month_grid;
    private Gtk.Label label;
    private bool showtoday;

    construct {
        label = new Gtk.Label (new GLib.DateTime.now_local ().format (_("%OB, %Y")));
        label.hexpand = true;
        label.margin_start = 6;
        label.xalign = 0;
        label.width_chars = 13;

        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("/io/elementary/desktop/wingpanel/datetime/ControlHeader.css");

        var label_style_context = label.get_style_context ();
        label_style_context.add_class ("header-label");
        label_style_context.add_provider (provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        var left_button = new Gtk.Button.from_icon_name ("pan-start-symbolic");
        var center_button = new Gtk.Button.from_icon_name ("office-calendar-symbolic");
        center_button.tooltip_text = _("Go to today's date");
        var right_button = new Gtk.Button.from_icon_name ("pan-end-symbolic");

        var box_buttons = new Gtk.Grid () {
            margin_end = 6,
            valign = Gtk.Align.CENTER
        };
        box_buttons.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
        box_buttons.add (left_button);
        box_buttons.add (center_button);
        box_buttons.add (right_button);

        calmodel = CalendarModel.get_default ();
        start_month = Util.get_start_of_month ();

        start_month_grid = create_grid ();
        start_month_grid.set_range (calmodel.data_range, calmodel.month_start);
        start_month_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);

        calmodel.change_month (-1);
        var left_grid = create_grid ();
        left_grid.set_range (calmodel.data_range, calmodel.month_start);
        left_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);

        calmodel.change_month (2);
        var right_grid = create_grid ();
        right_grid.set_range (calmodel.data_range, calmodel.month_start);
        right_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);
        calmodel.change_month (-1);

        carousel = new Hdy.Carousel () {
            interactive = true,
            expand = true,
            spacing = 15
        };

        carousel.add (left_grid);
        carousel.add (start_month_grid);
        carousel.add (right_grid);
        carousel.scroll_to (start_month_grid);

        position = 1;
        rel_postion = 0;
        showtoday = false;

        carousel.show_all ();

        column_spacing = 6;
        row_spacing = 6;
        margin_start = margin_end = 10;
        attach (label, 0, 0);
        attach (box_buttons, 1, 0);
        attach (carousel, 0, 1, 2);

        left_button.clicked.connect (() => {
            carousel.switch_child ((int) carousel.get_position () - 1, carousel.get_animation_duration ());
        });

        right_button.clicked.connect (() => {
            carousel.switch_child ((int) carousel.get_position () + 1, carousel.get_animation_duration ());
        });

        center_button.clicked.connect (() => {
            show_today ();
        });

        carousel.page_changed.connect ((index) => {
            calmodel.change_month (-rel_postion);
            if (position > index) {
                rel_postion--;
                position--;
            } else if (position < index) {
                rel_postion++;
                position++;
            } else if (showtoday) {
                showtoday = false;
                rel_postion = 0;
                position = (int) carousel.get_position ();
                label.label = calmodel.month_start.format (_("%OB, %Y"));
                start_month_grid.set_focus_to_today ();
                return;
            } else {
                calmodel.change_month (rel_postion);
                return;
            }
            calmodel.change_month (rel_postion);
            selected_date = null;
            selection_changed (selected_date);

            /* creates a new Grid, when the Hdy.Carousel is on it's first/last page*/
            if (index + 1 == (int) carousel.get_n_pages ()) {
                calmodel.change_month (1);
                var grid = create_grid ();
                grid.set_range (calmodel.data_range, calmodel.month_start);
                grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);
                carousel.add (grid);
                calmodel.change_month (-1);

            } else if (index == 0) {
                calmodel.change_month (-1);
                var grid = create_grid ();
                grid.set_range (calmodel.data_range, calmodel.month_start);
                grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);
                carousel.prepend (grid);
                calmodel.change_month (1);
                position++;
            }
            label.label = calmodel.month_start.format (_("%OB, %Y"));
        });
    }

    private DateTime.Widgets.Grid create_grid () {
        var grid = new DateTime.Widgets.Grid ();
        grid.show_all ();

        grid.on_event_add.connect ((date) => {
            show_date_in_maya (date);
            day_double_click ();
        });

        grid.selection_changed.connect ((date) => {
            selected_date = date;
            selection_changed (date);
        });

        return grid;
    }

    public void show_today () {
        showtoday = true;
        var today = Util.strip_time (new GLib.DateTime.now_local ());
        var start = Util.get_start_of_month (today);
        selected_date = today;
        if (start.equal (start_month)) {
            position -= rel_postion;
            carousel.switch_child (position, carousel.get_animation_duration ());
        } else {
            /*reset Carousel if center_child != the grid of the month of today*/
            carousel.no_show_all = true;
            foreach (unowned Gtk.Widget grid in carousel.get_children ()) {
                carousel.remove (grid);
            }

            start_month = Util.get_start_of_month ();
            calmodel.month_start = start_month;
            start_month_grid = create_grid ();
            start_month_grid.set_range (calmodel.data_range, calmodel.month_start);
            start_month_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);

            calmodel.change_month (-1);
            var left_grid = create_grid ();
            left_grid.set_range (calmodel.data_range, calmodel.month_start);
            left_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);

            calmodel.change_month (2);
            var right_grid = create_grid ();
            right_grid.set_range (calmodel.data_range, calmodel.month_start);
            right_grid.update_weeks (calmodel.data_range.first_dt, calmodel.num_weeks);
            calmodel.change_month (-1);

            carousel.add (left_grid);
            carousel.add (start_month_grid);
            carousel.add (right_grid);
            carousel.scroll_to (start_month_grid);
            label.label = calmodel.month_start.format (_("%OB, %Y"));
            carousel.no_show_all = false;
        }
    }

    // TODO: As far as maya supports it use the Dbus Activation feature to run the calendar-app.
    public void show_date_in_maya (GLib.DateTime date) {
        var command = "io.elementary.calendar --show-day %s".printf (date.format ("%F"));

        try {
            var appinfo = AppInfo.create_from_commandline (command, null, AppInfoCreateFlags.NONE);
            appinfo.launch_uris (null, null);
        } catch (GLib.Error e) {
            /*var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Unable To Launch Calendar"),
                _("The program \"io.elementary.calendar\" may not be installed"),
                "dialog-error"
            );
            dialog.show_error_details (e.message);
            dialog.run ();
            dialog.destroy ();*/
        }
    }
}

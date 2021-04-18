project(
    'datetime',
    'vala', 'c',
    version: '2.2.5'
)

i18n = import('i18n')
gnome = import('gnome')

gettext_name = meson.project_name() + '-indicator'

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))

add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format(gettext_name), language:'c')
add_project_arguments(['--vapidir', join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')

gresource = gnome.compile_resources(
    'gresource',
    join_paths('data', 'datetime.gresource.xml'),
    source_dir: 'data'
)

wingpanel_dep = dependency('hybridbar-1.0')
wingpanel_indicatorsdir = wingpanel_dep.get_pkgconfig_variable('indicatorsdir', define_variable: ['libdir', libdir])


libecal_dep = dependency('libecal-2.0', required: false)
if libecal_dep.found()
    libical_dep = dependency('libical-glib')
    add_project_arguments('--define=E_CAL_2_0', language: 'vala')
    add_project_arguments('-DLIBICAL_GLIB_UNSTABLE_API=1', language: 'c')
else
    libecal_dep = dependency('libecal-1.2', version: '>=3.8.0')
    libical_dep = dependency('libical')
    add_project_arguments('--vapidir', join_paths(meson.current_source_dir(), 'vapi'), language: 'vala')
endif

shared_module(
    meson.project_name(),
    gresource,
    'src/DateIterator.vala',
    'src/DateRange.vala',
    'src/Indicator.vala',
    'src/Widgets/EventRow.vala',
    'src/Widgets/PanelLabel.vala',
    'src/Widgets/calendar/CalendarModel.vala',
    'src/Widgets/calendar/CalendarView.vala',
    'src/Widgets/calendar/Grid.vala',
    'src/Widgets/calendar/GridDay.vala',
    'src/Widgets/calendar/Util.vala',
    'src/Services/TimeManager.vala',
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
       # dependency('granite'),
        dependency('gtk+-3.0'),
        libecal_dep,
        dependency('libedataserver-1.2'),
        dependency('libhandy-1'),
        libical_dep,
        wingpanel_dep,
    ],
    install: true,
    install_dir : wingpanel_indicatorsdir,
)

subdir('data')
subdir('po')

meson.add_install_script('meson/post_install.py')

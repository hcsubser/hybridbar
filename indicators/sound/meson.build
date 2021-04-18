project(
    'sound',
    'vala', 'c',
    version: '2.1.7'
)

gettext_name = meson.project_name() + '-indicator'
gnome = import('gnome')
i18n = import('i18n')

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))
libdir = join_paths(prefix, get_option('libdir'))

add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format(gettext_name), language:'c')

add_project_arguments(
    ['--vapidir', join_paths(meson.current_source_dir(), 'vapi')],
    language: 'vala'
)

asresources = gnome.compile_resources(
    'as-resources', 'data/mask.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

wingpanel_dep = dependency('hybridbar-1.0')
wingpanel_indicatorsdir = wingpanel_dep.get_pkgconfig_variable('indicatorsdir', define_variable: ['libdir', libdir])

shared_module(
    meson.project_name(),
    'src/Indicator.vala',
    'src/Widgets/DisplayWidget.vala',
    'src/Widgets/Scale.vala',
    'src/Widgets/MprisGui.vala',
    'src/Widgets/MprisWidget.vala',
    'src/Services/MprisClient.vala',
    'src/Services/Volume-control.vala',
    'src/Services/Manager.vala',
    'src/Services/Device.vala',
    'src/Services/MediaPlayer.vala',
    asresources,
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
		dependency('gio-unix-2.0'),
        dependency('gtk+-3.0'),
        dependency('libpulse'),
        dependency('libpulse-mainloop-glib'),
        dependency('libnotify'),
        dependency('libcanberra'),
        dependency('libcanberra-gtk3'),
        wingpanel_dep
    ],
    install: true,
    install_dir : wingpanel_indicatorsdir,
)

subdir('data')
subdir('po')

meson.add_install_script('meson/post_install.py')

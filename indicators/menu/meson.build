project(
  'slingshot',
  'vala', 'c',
  version : '2.7.1'
)

i18n = import('i18n')
gnome = import('gnome')

add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()),
    language: 'c'
)

asresources = gnome.compile_resources(
    'as-resources', 'data/icons.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))
libdir = join_paths(prefix, get_option('libdir'))

add_project_arguments(
    '-DPKGDATADIR="@0@"'.format(join_paths(get_option('prefix'), get_option('libdir'), 'hybridbar')),
    language: 'c'
)

pluginsdir = join_paths(prefix, get_option('libdir'), 'com.github.hcsubser.hybridbar.menu')
add_project_arguments(
    '-DPLUGINSDIR="@0@"'.format(pluginsdir),
    language: 'c'
)

glib_dep = dependency('glib-2.0')
gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk+-3.0')
gobject_dep = dependency('gobject-2.0')
libsoup_dep = dependency('libsoup-2.4')
gio_unix_dep = dependency('gio-unix-2.0')
json_glib_dep = dependency('json-glib-1.0')
libgnome_menu_dep = dependency('libgnome-menu-3.0')
libhandy_dep = dependency('libhandy-1', version: '>= 0.83.0')
wingpanel_dep = dependency('hybridbar-1.0')
posix_dep = meson.get_compiler('vala').find_library('posix')

#zeitgeist_dep = []

#if get_option('with-zeitgeist')
#    zeitgeist_dep = dependency('zeitgeist-2.0')
#    add_project_arguments('--define=HAVE_ZEITGEIST', language: 'vala')
#endif

subdir('src')
subdir('data')
subdir('po')

meson.add_install_script('meson/post_install.py')

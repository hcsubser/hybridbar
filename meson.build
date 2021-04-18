project(
    'hybridbar',
    'c', 'vala',
    version: '3.0.0',
)

lib_version = '3.0.0'

add_project_arguments([
        '--vapidir=' + join_paths(meson.source_root(), 'vapi'),
    ],
    language: 'vala',
)

add_project_arguments([
        '-DGETTEXT_PACKAGE="wingpanel"',
        '-DG_LOG_DOMAIN="wingpanel"'
    ],
    language: 'c'
)

indicators_dir = join_paths(get_option('prefix'), get_option('libdir'), 'hybridbar')

i18n = import('i18n')
gnome = import('gnome')
pkg = import('pkgconfig')

glib_dep = dependency('glib-2.0', version: '>=2.32')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
gmodule_dep = dependency('gmodule-2.0')
gtk_dep = dependency('gtk+-3.0', version: '>=3.10')
gee_dep = dependency('gee-0.8')
gtkls_dep = dependency('gtk-layer-shell-0')

subdir('data')
subdir('lib')
subdir('src')


vapigen = find_program('vapigen', required: false)
if vapigen.found()
	subdir('vapi')
endif

meson.add_install_script('data/post_install.py')

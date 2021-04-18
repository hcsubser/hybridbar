project(
    'session',
    'vala', 'c',
    version: '2.2.8'
)

i18n = import('i18n')
gettext_name = meson.project_name() + '-indicator'

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))

add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format(gettext_name), language:'c')
add_project_arguments(['--vapidir', join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')

wingpanel_dep = dependency('hybridbar-1.0')
wingpanel_indicatorsdir = wingpanel_dep.get_pkgconfig_variable('indicatorsdir', define_variable: ['libdir', libdir])

shared_module(
    meson.project_name(),
    'src/Indicator.vala',
    'src/Widgets/EndSessionDialog.vala',
    'src/Widgets/UserBox.vala',
    'src/Widgets/UserListBox.vala',
    'src/Services/DbusInterfaces.vala',
    'src/Services/UserManager.vala',
    'src/Services/EndSessionDialogServer.vala',
    dependencies: [
        dependency('accountsservice'),
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
        dependency('gtk+-3.0'),
        dependency('libhandy-1', version: '>=0.90.0'),
        wingpanel_dep
    ],
    install: true,
    install_dir : wingpanel_indicatorsdir
)

subdir('data')
subdir('po')

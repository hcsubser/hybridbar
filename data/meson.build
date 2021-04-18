#install_data(
#    'autostart.desktop',
#    rename: 'io.elementary.wingpanel.desktop',
#    install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'autostart')
#)

# Use GResource
if get_option('example')
    subdir('sample')
endif

css_gresource = gnome.compile_resources(
    'gresource_css',
    meson.project_name() + '.gresource.xml'
)
install_data(
    'com.github.hcsubser.hybridbar.gschema.xml',
    install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas')
)

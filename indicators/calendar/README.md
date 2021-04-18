# Wingpanel Date &amp; Time Indicator
[![Packaging status](https://repology.org/badge/tiny-repos/wingpanel-indicator-datetime.svg)](https://repology.org/metapackage/wingpanel-indicator-datetime)
[![Translation status](https://l10n.elementary.io/widgets/wingpanel/-/wingpanel-indicator-datetime/svg-badge.svg)](https://l10n.elementary.io/engage/wingpanel/?utm_source=widget)

![Screenshot](data/screenshot.png?raw=true)

## Building and Installation

You'll need the following dependencies:

* gobject-introspection
* libecal1.2-dev
* libedataserver1.2-dev
* libical-dev
* libgranite-dev
* libwingpanel-dev
* meson
* valac >= 0.40.3

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install

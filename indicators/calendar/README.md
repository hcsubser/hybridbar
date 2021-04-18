# Hybridbar Date &amp; Time Indicator

## Building and Installation

You'll need the following dependencies:

* gobject-introspection
* libecal1.2-dev
* libedataserver1.2-dev
* libical-dev
* libhybridbar-dev
* meson
* valac >= 0.40.3

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install


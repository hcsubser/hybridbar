# Hybridbar Network Indicator
## Building and Installation

You'll need the following dependencies:

* gobject-introspection
* libnm-dev
* libnma-dev
* libhybridbar-dev
* meson
* valac

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install


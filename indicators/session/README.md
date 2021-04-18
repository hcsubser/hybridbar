# Hybridbar Session Indicator
## Building and Installation

You'll need the following dependencies:

    libaccountsservice-dev
    libgirepository1.0-dev
    libglib2.0-dev
    libgtk-3-dev
    libhandy-1-dev >= 0.90.0
    libhybridbar-dev
    meson
    valac

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install


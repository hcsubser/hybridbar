# Wingpanel Session Indicator
[![Translation status](https://l10n.elementary.io/widgets/wingpanel/-/wingpanel-indicator-session/svg-badge.svg)](https://l10n.elementary.io/engage/wingpanel/?utm_source=widget)

![Screenshot](data/screenshot.png?raw=true)

## Building and Installation

You'll need the following dependencies:

    libaccountsservice-dev
    libgirepository1.0-dev
    libglib2.0-dev
    libgranite-dev >= 5.3.0
    libgtk-3-dev
    libhandy-1-dev >= 0.90.0
    libwingpanel-dev
    meson
    valac

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install

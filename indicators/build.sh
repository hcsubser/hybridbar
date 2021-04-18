#!/usr/bin/env bash

export DIR=$(dirname $(readlink -f "${0}"))

cd "$DIR/calendar"
meson build $1
ninja -C build install

cd "$DIR/menu"
meson build $1
ninja -C build install

cd "$DIR/network"
meson build $1
ninja -C build install

cd "$DIR/session"
meson build $1
ninja -C build install

cd "$DIR/sound"
meson build $1
ninja -C build install

cd "$DIR/system-tray"
meson build $1
ninja -C build install

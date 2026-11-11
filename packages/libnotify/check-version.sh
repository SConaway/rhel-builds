#!/usr/bin/env bash
# libnotify is released as tarballs on download.gnome.org; the GitHub mirror has
# no Releases, so the generic checker can't be used.
set -euo pipefail

curl -fsSL https://download.gnome.org/sources/libnotify/0.8/ \
    | grep -oP 'libnotify-\K[0-9]+(\.[0-9]+)+(?=\.tar\.xz")' \
    | sort -uV \
    | tail -n1

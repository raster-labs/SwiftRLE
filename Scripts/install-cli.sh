#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prefix=${PREFIX:-/usr/local}
stage=${DESTDIR:-}
case "$prefix" in /*) ;; *) echo 'PREFIX must be absolute' >&2; exit 2 ;; esac
binary=${1:-"$root/.build/release/swiftrle-cli"}
test -x "$binary"
test "$("$binary" --version)" = "$(cat "$root/VERSION")"
mkdir -p "$stage$prefix/bin" "$stage$prefix/share/man/man1"
install -m 755 "$binary" "$stage$prefix/bin/swiftrle-cli"
install -m 644 "$root/ManPages/swiftrle-cli.1" "$stage$prefix/share/man/man1/swiftrle-cli.1"

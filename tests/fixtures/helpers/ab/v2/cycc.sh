#!/bin/sh
# ab golden, the NEW ref's "compiler": compiles its own source, refuses the old one (rc 4).
src=$(cat)
case "$src" in *V2*) exit 0 ;; esac
exit 4

#!/bin/sh
# ab golden, the OLD ref's "compiler": compiles its own source, dies of SIGSEGV on the new one.
src=$(cat)
case "$src" in *V2*) kill -SEGV $$ ;; esac
exit 0

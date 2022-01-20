#!/bin/sh -e
# symlink this file to a directory in PATH to run dtas (or anything in bin/*)
# without needing perms to install globally.  Used by "make symlink-install"
p=$(realpath "$0" || readlink "$0"); # neither is POSIX, but common
p=$(dirname "$p") c=$(basename "$0"); c="${c%.sh}"
if test -x "$p/bin/$c"; then exec ${RUBY-ruby} -I"$p"/lib "$p/bin/$c" "$@";
else exec ${PERL-perl} -I"$p"/lib "$p/script/$c" "$@"; fi
: this script is too short to copyright

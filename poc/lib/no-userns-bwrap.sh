#!/bin/sh
# A `bwrap' that fails the way the real one does on a kernel without
# unprivileged user namespaces, which is the one thing every harness in this
# tree needs and the one thing that cannot be turned off here to test for.
#
# `just sandbox-refuses' puts this in front of the real bwrap on PATH and
# requires a harness to name the requirement -- and to quote this message, so
# that the reason reaching the reader is bubblewrap's own rather than a guess.
echo "bwrap: setting up uid map: Permission denied" >&2
exit 1

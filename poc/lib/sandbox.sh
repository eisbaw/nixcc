# Sourced as the first thing every PoC's run.sh does. Re-execs the caller
# inside a bubblewrap sandbox whose scratch filesystem is a tmpfs, and leaves
# $work pointing at it.
#
# WHY. These harnesses do a lot of scratch work -- a copy of the PoC directory
# per mutation, another per guard case, a ladder of generated sources -- and
# used to end with `rm -rf "$work"' under an EXIT trap. Two reasons that is
# worth replacing rather than keeping:
#
#   * A tmpfs is reclaimed by the kernel when the last process in the mount
#     namespace exits. Nothing has to remember to delete anything, no trap can
#     fire at the wrong moment, and a partially-failed remove cannot leave a
#     stale mutation behind for the next one to inherit. The old
#     `rm -rf "$mut"; cp -r "$poc" "$mut"' pattern was one failed remove away
#     from testing a mutation that was still half the previous one.
#   * Delete-shaped commands in a harness are a liability of their own. There
#     are now none in this tree, and `just lint' greps to keep it that way.
#
# WHAT IS AND IS NOT SANDBOXED. This is the SCRATCH sandbox, not a hermeticity
# claim: the host filesystem is bound through as it is, and only /tmp is
# replaced. The harnesses need nix, python, the lcc sources, the cross
# toolchain and the user's nix store, and hiding any of it would be a different
# piece of work. The hermeticity claim in this tree is made separately and much
# more tightly by poc/05-loop/closed-loop.sh, which binds nothing but nix's own
# runtime closure. Keeping HOME as it is also keeps nix's eval cache, which a
# tmpfs HOME would have silently thrown away.
#
# DEBUGGING. On a failure the tmpfs goes with the process, so the artifacts
# that used to be kept under `artifacts kept in ...' are gone. Set
# NIXCC_SCRATCH to a directory and it is bound there instead of being a tmpfs,
# and everything survives:
#
#     mkdir -p /var/tmp/nixcc && NIXCC_SCRATCH=/var/tmp/nixcc just poc-lexer
#
# That directory is then yours to keep or remove; this harness will not touch
# it beyond writing into it.

# shellcheck shell=bash

nixcc_sandbox_scratch=/tmp/nixcc

if [ -z "${NIXCC_SANDBOX:-}" ]; then
  nixcc_self=$(readlink -f "$0")
  command -v bwrap >/dev/null 2>&1 || {
    echo "no \`bwrap' on PATH. These harnesses run their scratch work inside a" >&2
    echo "bubblewrap sandbox whose scratch filesystem is a tmpfs, so that" >&2
    echo "nothing has to be deleted afterwards. Run this inside \`nix develop'," >&2
    echo "which provides it." >&2
    exit 2
  }
  # Probe before committing, so that a kernel without unprivileged user
  # namespaces is named rather than showing up as an inscrutable failure
  # somewhere inside the harness. bwrap's own diagnostic is the useful half, so
  # it is quoted rather than replaced.
  if ! nixcc_probe=$(bwrap --dev-bind / / --tmpfs /tmp --die-with-parent \
                     -- /bin/sh -c : 2>&1); then
    echo "bubblewrap cannot create a sandbox here:" >&2
    echo "  $nixcc_probe" >&2
    echo >&2
    echo "This needs UNPRIVILEGED USER NAMESPACES. Check that" >&2
    echo "/proc/sys/user/max_user_namespaces is above zero and, on kernels that" >&2
    echo "have it, that /proc/sys/kernel/unprivileged_userns_clone is 1. Some" >&2
    echo "hardened kernels and some container runtimes disable them outright," >&2
    echo "and on such a machine these harnesses cannot run at all -- this is a" >&2
    echo "harness fault, not a verdict on anything they would have tested." >&2
    exit 2
  fi
  # /proc/stat and nproc are read INSIDE the sandbox by poc/lib/contention.py,
  # which decides whether a linearity verdict means anything. Neither is
  # namespaced by a plain user namespace, so both describe the host -- but that
  # is a property of this kernel rather than a guarantee, and a silently
  # namespaced /proc would invalidate every verdict these harnesses render
  # without changing a single line of output. So the host's figures go in as
  # environment variables and poc/lib/selftest.py asserts they came back.
  nixcc_cores=$(nproc)
  nixcc_busy=$(awk '/^cpu /{print $2+$3+$4+$7+$8+$9}' /proc/stat)

  # A bound directory rather than the tmpfs when NIXCC_SCRATCH asks for one.
  # Without it the mount is simply a directory on the /tmp tmpfs above, which
  # the kernel reclaims with the namespace.
  nixcc_mount=()
  if [ -n "${NIXCC_SCRATCH:-}" ]; then
    [ -d "$NIXCC_SCRATCH" ] || {
      echo "NIXCC_SCRATCH=$NIXCC_SCRATCH is not a directory" >&2; exit 2; }
    nixcc_mount=(--bind "$NIXCC_SCRATCH" "$nixcc_sandbox_scratch")
  fi

  exec bwrap \
    --dev-bind / / \
    --tmpfs /tmp \
    "${nixcc_mount[@]}" \
    --die-with-parent \
    --setenv NIXCC_SANDBOX 1 \
    --setenv NIXCC_HOST_CORES "$nixcc_cores" \
    --setenv NIXCC_HOST_BUSY "$nixcc_busy" \
    --setenv TMPDIR /tmp \
    -- "$BASH" "$nixcc_self" "$@"
fi

# Inside. The tmpfs is empty, so this is the one mkdir that has to happen.
mkdir -p "$nixcc_sandbox_scratch"
# shellcheck disable=SC2034  # $work is what the sourcing run.sh uses
work=$nixcc_sandbox_scratch

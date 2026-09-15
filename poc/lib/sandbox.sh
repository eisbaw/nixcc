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
#     are now none in this tree, and `just no-deletes', which `just lint'
#     runs, greps to keep it that way.
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
# Each run gets its own subdirectory under it, named after the harness process,
# so a second run does not trip over what the first one left -- which the first
# version of this did, on the first plain `mkdir' a harness reached, with a
# message naming neither the cause nor the variable. The directory is then
# yours: nothing here removes anything from it, ever.
#
# `just poc' prints the variable's name when a PoC exits non-zero, because a
# debugging aid nobody is told about on the day they need it is not one.

# shellcheck shell=bash

nixcc_sandbox_scratch=/tmp/nixcc

if [ -n "${NIXCC_SANDBOX:-}" ] && [ -z "${NIXCC_HOST_CORES:-}" ]; then
  echo "NIXCC_SANDBOX is set but NIXCC_HOST_CORES is not, so this is not a" >&2
  echo "sandbox poc/lib/sandbox.sh built. That variable is how a harness knows" >&2
  echo "it is already inside one; setting it by hand skips the sandbox, leaves" >&2
  echo "scratch state on the real filesystem and lets one run inherit the last" >&2
  echo "one's -- which is the failure this machinery exists to make impossible." >&2
  exit 2
fi

if [ -z "${NIXCC_SANDBOX:-}" ]; then
  nixcc_self=$(readlink -f "$0")
  # A checkout under /tmp cannot work: the tmpfs below replaces /tmp and takes
  # the harness with it, and bwrap then execs a path that no longer exists and
  # says only "No such file or directory" about a file that plainly does.
  case "$nixcc_self" in
    /tmp/*) echo "this harness lives under /tmp ($nixcc_self), and it runs its" >&2
            echo "scratch work on a tmpfs mounted over /tmp -- which would take" >&2
            echo "the harness itself with it. Check the tree out elsewhere." >&2
            exit 2 ;;
  esac
  [ -n "${BASH:-}" ] && [ -x "$BASH" ] || {
    echo "\$BASH is not set to an executable, so this was not started by bash," >&2
    echo "and there is nothing to re-exec the harness with inside the sandbox." >&2
    echo "Run it as \`bash <harness>/run.sh', which is how the Justfile does." >&2
    exit 2
  }
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
  # /proc/stat and the core count are read INSIDE the sandbox by
  # poc/lib/contention.py, which decides whether a linearity verdict means
  # anything -- busy_cpu_seconds() and os.cpu_count(). Neither is
  # namespaced by a plain user namespace, so both describe the host -- but that
  # is a property of this kernel rather than a guarantee, and a silently
  # namespaced /proc would invalidate every verdict these harnesses render
  # without changing a single line of output. So the host's figures go in as
  # environment variables and poc/lib/selftest.py asserts they came back.
  # Read through contention.py itself rather than through `nproc' and an awk
  # sum of /proc/stat. Two reasons, both found by review. `nproc' is
  # affinity-aware and os.cpu_count() is not, so under `taskset' or a cgroup
  # cpuset the two disagree by construction and the check inside would have
  # reported a sandbox virtualising the core count when nothing was -- a false
  # diagnostic pointing at bubblewrap. And an awk copy of busy_cpu_seconds()
  # is a second definition of a number this tree has exactly one definition
  # of, in a module whose LIMITS section contemplates changing it.
  nixcc_figures=$(python3 -c '
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1])))
import contention
print(contention.cores(), contention.busy_cpu_seconds())
' "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")") || {
    echo "cannot read this machine's core count and busy counter through" >&2
    echo "poc/lib/contention.py, which is what the harnesses inside the" >&2
    echo "sandbox will read them with. Refusing to start one." >&2
    exit 2
  }
  nixcc_cores=${nixcc_figures%% *}
  nixcc_busy=${nixcc_figures##* }

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

# Inside. A subdirectory of this run's own: on the tmpfs that is merely tidy,
# but under a bound NIXCC_SCRATCH it is what lets the same directory serve a
# second run. Every plain `mkdir' further down then still means "this must not
# already exist", which is what those call sites want it to mean.
mkdir -p "$nixcc_sandbox_scratch/run-$$"
# shellcheck disable=SC2034  # $work is what the sourcing run.sh uses
work=$nixcc_sandbox_scratch/run-$$

# What the three ladder harnesses do with poc/lib/selftest.py's three exit
# statuses. Sourced, not run.
#
# WHY IT IS HERE AND NOT IN EACH run.sh. It was in each of them for about an
# hour, and had already drifted: two harnesses explained themselves at the call
# site and the third said nothing, and the three "carrying on" messages were
# three different wordings of one policy. One policy, one copy -- the same
# argument poc/lib/sandbox.sh and poc/lib/mutant.sh are made of.
#
# THE POLICY. selftest.py renders three outcomes, and they are not three
# degrees of the same thing:
#
#   0  the contention guard was shown to measure. Carry on.
#   2  the harness or its inputs are broken. Nothing below is worth running.
#   3  the machine would not hold still long enough to show either way. Neither
#      a pass nor a failure -- so it is CARRIED to the end of the harness
#      rather than propagated here, because everything between the self-test
#      and the ladder is deterministic, needs no free cores, and would
#      otherwise be lost to a busy machine for no reason.
#   1  the guard is not measuring what it claims. Stop.
#
# WHAT EXIT 3 IS ALLOWED TO REACH, at the end. A ladder PASS, and only that.
# Its verdict rests entirely on a guard this run never managed to show was
# measuring anything, so a pass is not one. A ladder FAIL is left alone: it is
# arguable that a linearity FAIL under an unverified guard is unreadable too,
# but downgrading it would relabel a red as a refusal, and `just poc' reports a
# refusal with the words "Every other check in them passed", which would then
# be false. A harness fault (2) from the ladder is a defect and is left alone
# for the same reason.

# shellcheck shell=bash

# nixcc_selftest LIBDIR SCRATCHDIR -- sets $nixcc_selftest to 0 or 3, or exits.
nixcc_selftest() {
  nixcc_selftest=0
  python3 "${1:?usage: nixcc_selftest LIBDIR SCRATCHDIR}/selftest.py" \
    "${2:?usage: nixcc_selftest LIBDIR SCRATCHDIR}" || nixcc_selftest=$?
  case "$nixcc_selftest" in
    0) ;;
    3) echo "NO VERDICT: the contention self-test could not be taken on this" >&2
       echo "machine. Carrying on with the checks that do not need a quiet one;" >&2
       echo "this PoC will end with no verdict rather than a pass." >&2 ;;
    *) exit "$nixcc_selftest" ;;
  esac
}

# nixcc_selftest_verdict LADDER-STATUS -- sets $nixcc_verdict to what this
# harness should exit with, given what the ladder said and what the self-test
# managed to show.
nixcc_selftest_verdict() {
  nixcc_verdict=${1:?usage: nixcc_selftest_verdict LADDER-STATUS}
  if [ "${nixcc_selftest:-0}" = 3 ] && [ "$nixcc_verdict" = 0 ]; then
    echo "NO VERDICT: the ladder above read as linear, but the contention" >&2
    echo "self-test could not be taken, so the guard that decides whether the" >&2
    echo "ladder may speak at all was never shown to measure anything. That is" >&2
    echo "not a pass." >&2
    nixcc_verdict=3
  fi
}

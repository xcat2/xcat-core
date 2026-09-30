#!/bin/bash
#
# Run a fast subset of the unit tests: the Perl .t files with prove and the shell .bats files
# with bats, in one command, from the source tree. No build, no installed xCAT, no cluster.
#
# WHY THIS EXISTS. Delta debugging a change set runs the suite once per candidate. The
# end-to-end suite provisions machines and costs 45 to 90 minutes a run, so the rounds run on a
# fast oracle instead, and the slow suite runs once on the set that settles. This is that fast
# oracle, and it is useful on its own: it is the same two commands CI runs, without the wait.
#
#   xCAT-test/quick.sh                      every unit test and every bats file
#   xCAT-test/quick.sh path/a.t path/b.bats only those, in the order given
#   xCAT-test/quick.sh -f list.txt          the files named in list.txt, one per line
#
# Exit status is 0 only when every file passed. A missing file is an error, not a skip: a fast
# oracle that silently runs nothing reports PASS for a tree that contains none of the tests.

set -u -o pipefail

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
files=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage 0 ;;
        -f|--from) shift; [ -r "${1:-}" ] || { echo "quick: cannot read list '${1:-}'" >&2; exit 2; }
                   while read -r line; do
                       case "$line" in ''|\#*) continue ;; esac
                       files+=("$line")
                   done < "$1" ;;
        -*) echo "quick: unknown option '$1'" >&2; usage 2 ;;
        *)  files+=("$1") ;;
    esac
    shift
done

cd "$root" || exit 2

if [ "${#files[@]}" -eq 0 ]; then
    echo "[quick] whole fast suite: prove -r xCAT-test/unit, then bats -r xCAT-test/bats"
    rc=0
    prove -r xCAT-test/unit || rc=1
    bats  -r xCAT-test/bats || rc=1
    exit $rc
fi

# A named file that is absent means the caller asked for a test this tree does not have. Say so
# and fail: reporting PASS here is how a minimization drops the commit that adds a test.
missing=()
for f in "${files[@]}"; do [ -e "$f" ] || missing+=("$f"); done
if [ "${#missing[@]}" -gt 0 ]; then
    printf '[quick] MISSING from this tree, refusing to report a result:\n' >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 2
fi

perl_tests=(); bats_tests=()
for f in "${files[@]}"; do
    case "$f" in
        *.t)    perl_tests+=("$f") ;;
        *.bats) bats_tests+=("$f") ;;
        *)      echo "quick: '$f' is neither a .t nor a .bats" >&2; exit 2 ;;
    esac
done

rc=0
if [ "${#perl_tests[@]}" -gt 0 ]; then
    echo "[quick] prove ${#perl_tests[@]} Perl test(s)"
    prove "${perl_tests[@]}" || rc=1
fi
if [ "${#bats_tests[@]}" -gt 0 ]; then
    echo "[quick] bats ${#bats_tests[@]} shell test(s)"
    bats "${bats_tests[@]}" || rc=1
fi

[ $rc -eq 0 ] && echo "[quick] PASS (${#files[@]} file(s))" || echo "[quick] FAIL"
exit $rc

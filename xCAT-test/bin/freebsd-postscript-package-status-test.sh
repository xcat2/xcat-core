#!/bin/sh

# Select this script only on a disposable qualified node. It temporarily
# corrupts its own completed package evidence, restoring the original files.
# The package operation, initial installation and package database remain real.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 1 ]
workspace=$1
case "$workspace" in /*) ;; *) exit 2 ;; esac
case "$workspace" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
run=${XCAT_FREEBSD_POSTSCRIPT_RUN:-}
ordinal=${XCAT_FREEBSD_POSTSCRIPT_ENTRY:-}
[ "${#run}" -eq 32 ]
case "$run" in *[!0-9a-f]*) exit 2 ;; esac
case "$ordinal" in ''|*[!0-9]*) exit 2 ;; esac
[ "$ordinal" -gt 0 ] && [ "$ordinal" -le 4096 ]
[ "$(cat /var/db/xcat/postscripts/active)" = "$run" ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
worker=/usr/local/libexec/xcat-postscript
state=/var/db/xcat/postscripts/runs/$run
adapters=$(dirname "$0")
receipt=$state/packages.result
mode=$(awk -F '\t' '$1 == "mode" {print $2}' "$receipt")
case "$mode" in verify) wrong_mode=update ;; update) wrong_mode=verify ;; *) exit 2 ;; esac
native_result=$state/packages/local-$mode.result
receipt_digest=$(sha256 -q "$receipt")
cp -p "$receipt" "$workspace/package-receipt.before"
cp -p "$native_result" "$workspace/native-result.before"
cp -p /var/db/xcat-qualification/package-actions "$workspace/actions.before"
restore=
backup=
receipt_backup=
case_name=
restore_file()
{
    if [ -n "$restore" ]; then
        if [ -e "$restore" ]; then
            cp -p "$restore" "$workspace/$case_name.mutant"
            rm "$restore"
        fi
        mv "$backup" "$restore"
        restore=
    fi
    if [ -n "$receipt_backup" ]; then
        cp -p "$receipt" "$workspace/$case_name.receipt.mutant"
        rm "$receipt"
        mv "$receipt_backup" "$receipt"
        receipt_backup=
    fi
}
finish()
{
    result=$?
    trap - EXIT
    restore_file || result=1
    printf '%s\n' "$result" > "$workspace/exit-code"
    exit "$result"
}
trap finish EXIT
invoke()
{
    case_name=$1
    shift
    status=0
    "$@" > "$workspace/$case_name.stdout" 2> "$workspace/$case_name.stderr" || status=$?
    printf '%s\n' "$status" > "$workspace/$case_name.status"
}
for script in ospkgs otherpkgs; do
    invoke "$script" "$adapters/$script"
    [ "$status" -eq 0 ]
    grep -Fx "Package operation $mode: no-change (78 packages, 0 changes, 0 actions)." "$workspace/$script.stdout"
    grep -Fx "Receipt: $receipt_digest" "$workspace/$script.stdout"
    [ ! -s "$workspace/$script.stderr" ]
    printf 'PASS %s\n' "$script"
done
invoke options "$adapters/otherpkgs" --repoonly
[ "$status" -eq 1 ]
grep -F 'do not accept repository options' "$workspace/options.stderr"
printf 'PASS options\n'
for fault in missing mode native evidence count; do
    case_name=$fault
    case "$fault" in
    missing|mode) restore=$receipt ;;
    native|count) restore=$native_result ;;
    evidence) restore=$state/packages/before ;;
    esac
    original_digest=$(sha256 -q "$restore")
    backup=$workspace/$fault.original
    mv "$restore" "$backup"
    if [ "$fault" != missing ]; then
        cp -p "$backup" "$restore"
        chmod 0600 "$restore"
        case "$fault" in
        mode) sed "s/^mode.*/mode\t$wrong_mode/" "$backup" > "$restore" ;;
        native|count) sed 's/^packages.*/packages\t77/' "$backup" > "$restore" ;;
        evidence) printf 'corrupt\n' >> "$restore" ;;
        esac
    fi
    if [ "$fault" = count ]; then
        receipt_backup=$workspace/count.receipt.original
        mv "$receipt" "$receipt_backup"
        sed "s/^native-sha256.*/native-sha256\t$(sha256 -q "$native_result")/" "$receipt_backup" > "$receipt"
    fi
    invoke "$fault" "$worker" package-status "$run" "$ordinal"
    [ "$status" -eq 125 ]
    case "$fault" in
    missing) message='Invalid state file' ;;
    mode) message='Package result binding differs' ;;
    native) message='Native package result differs' ;;
    evidence) message='Native package evidence differs' ;;
    count) message='Package operation count differs from installed state' ;;
    esac
    grep -F "$message" "$workspace/$fault.stderr"
    restored_path=$restore
    restore_file
    [ "$(sha256 -q "$restored_path")" = "$original_digest" ]
    printf 'PASS %s\n' "$fault"
done
invoke restored "$adapters/otherpkgs"
[ "$status" -eq 0 ]
cmp "$workspace/otherpkgs.stdout" "$workspace/restored.stdout"
cmp "$workspace/package-receipt.before" "$receipt"
cmp "$workspace/native-result.before" "$native_result"
cmp "$workspace/actions.before" /var/db/xcat-qualification/package-actions
printf 'PASS restored\nPASS cases=9\n'

#!/bin/sh

# The reference is a disposable native root retained after an interrupted
# app/lib 1-to-2 upgrade. It contains the real old helper, requests and roster.
# The fourth and fifth arguments bind the previous recovery helper and its SHA256.
# Run only on a disposable FreeBSD node. Keep every result for readback.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 5 ]
workspace=$1
helper=$2
reference=$3
previous=$4
previous_digest=$5
for path in "$workspace" "$helper" "$reference" "$previous"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
done
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ]
[ ! -L "$workspace" ]
[ -x "$helper" ]
[ -x "$previous" ]
[ "${#previous_digest}" -eq 64 ]
case "$previous_digest" in *[!0-9a-f]*) exit 2 ;; esac
[ "$(sha256 -q "$previous")" = "$previous_digest" ]
[ -f "$reference/work/interrupted/before" ]
[ -f "$reference/work/interrupted/local-update.started" ]
[ ! -e "$reference/work/interrupted/local-update.result" ]
grep -q '^xcat-update-app 2 ' "$reference/work/installed.after"
grep -q '^xcat-update-lib 2 ' "$reference/work/installed.after"
mkdir -m 0700 "$workspace"
active=
finish()
{
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$active" ]; then umount "$active" || status=1; fi
    printf '%s\n' "$status" > "$workspace/exit-code"
    exit "$status"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
inside()
{
    env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C chroot "$root" "$@"
}
invoke()
{
    label=$1
    shift
    status=0
    inside "$@" > "$case_dir/$label.stdout" 2> "$case_dir/$label.stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/$label.status"
}
count=0
controls=0
printf 'RECOVERY_PREVIOUS_SHA256 %s\n' "$previous_digest"
for name in recover missing-before missing-start invalid-start invalid-before prior-drift \
    missing-package unexpected-package metadata-drift prior-flags pending-trigger \
    missing-archive altered-archive missing-database linked-database \
    verify-scope rejected-operation missing-actions empty-actions partial-actions \
    wrong-old wrong-new wrong-type wrong-ordinal duplicate-action ambiguous-start manifest-update; do
    case_dir=$workspace/$name
    root=$case_dir/root
    mkdir -m 0700 "$case_dir"
    mkdir -m 0755 "$root"
    cp -a "$reference/." "$root/"
    install -m 0555 "$helper" "$root/tools/candidate"
    install -m 0555 "$previous" "$root/tools/previous"
    [ "$(sha256 -q "$root/tools/previous")" = "$previous_digest" ]
    operation=$root/work/interrupted
    active=$root/dev
    mount -t devfs devfs "$active"
    devfs -m "$active" rule apply hide
    for device in null zero random urandom; do devfs -m "$active" rule apply path "$device" unhide; done
    case "$name" in
    missing-before) mv "$operation/before" "$case_dir/retained-before" ;;
    missing-start) mv "$operation/local-update.started" "$case_dir/retained-start" ;;
    invalid-start) printf 'invalid\n' > "$operation/local-update.started" ;;
    invalid-before) printf 'invalid\n' > "$operation/before" ;;
    prior-drift)
        awk -F '\t' 'BEGIN {OFS=FS} $4=="xcat-update-lib" {$5="9"} {print}' \
            "$operation/prior-request" > "$case_dir/changed-prior"
        install -m 0400 "$case_dir/changed-prior" "$operation/prior-request"
        ;;
    missing-package)
        inside /tools/pkg -C /work/setup.conf -R /work/repos delete -fy xcat-update-lib \
            > "$case_dir/setup.stdout" 2> "$case_dir/setup.stderr"
        ;;
    unexpected-package)
        inside /tools/pkg -C /work/setup.conf -R /work/repos add -q /fixtures/extra.pkg \
            > "$case_dir/setup.stdout" 2> "$case_dir/setup.stderr"
        ;;
    metadata-drift)
        inside /tools/pkg -C /work/setup.conf -R /work/repos annotate -Ay xcat-update-app recovery unexpected \
            > "$case_dir/setup.stdout" 2> "$case_dir/setup.stderr"
        ;;
    prior-flags)
        inside /tools/pkg -C /work/setup.conf -R /work/repos unlock -y xcat-update-outside \
            > "$case_dir/setup.stdout" 2> "$case_dir/setup.stderr"
        ;;
    pending-trigger)
        mkdir -m 0755 "$root/var/db/pkg/triggers"
        printf 'return 0\n' > "$root/var/db/pkg/triggers/Pending1"
        ;;
    missing-archive) mv "$operation/archives/p1.pkg" "$case_dir/retained-archive" ;;
    altered-archive) printf corrupt >> "$operation/archives/p1.pkg" ;;
    verify-scope)
        sed 's/local-update/local-verify/' "$operation/local-update.started" > "$case_dir/verify-started"
        mv "$operation/local-update.started" "$case_dir/retained-start"
        install -m 0600 "$case_dir/verify-started" "$operation/local-verify.started"
        ;;
    rejected-operation)
        cp -p "$root/work/same-version/local-update.rejected" "$operation/local-update.rejected"
        ;;
    missing-actions) mv "$operation/actions" "$case_dir/retained-actions" ;;
    empty-actions) head -n 1 "$operation/actions" > "$case_dir/changed-actions" ;;
    partial-actions) head -n 2 "$operation/actions" > "$case_dir/changed-actions" ;;
    wrong-old|wrong-new|wrong-type|wrong-ordinal)
        case "$name" in
        wrong-old) field=5; value=9 ;;
        wrong-new) field=6; value=9 ;;
        wrong-type) field=3; value=0 ;;
        wrong-ordinal) field=2; value=0 ;;
        esac
        awk -F '\t' -v field="$field" -v value="$value" 'BEGIN {OFS=FS} NR==2 {$field=value} {print}' \
            "$operation/actions" > "$case_dir/changed-actions"
        ;;
    duplicate-action)
        awk -F '\t' 'BEGIN {OFS=FS} {print} NR==2 {$2=3; extra=$0} END {print extra}' \
            "$operation/actions" > "$case_dir/changed-actions"
        ;;
    ambiguous-start)
        sed 's/local-update/local-verify/' "$operation/local-update.started" > "$operation/local-verify.started"
        chmod 0600 "$operation/local-verify.started"
        ;;
    manifest-update)
        printf 'format\txcat-freebsd-local-manifests-1\n' > "$case_dir/changed-request"
        sed -n '2p' "$operation/request" >> "$case_dir/changed-request"
        for id in p0 p1; do
            tar -xOf "$operation/archives/$id.pkg" +MANIFEST > "$operation/archives/$id.manifest"
            chmod 0400 "$operation/archives/$id.manifest"
            row=$(awk -F '\t' -v id="$id" '$1=="package" && $2==id {print}' "$operation/request")
            printf '%s\t%s\t%s\n' "$row" "$(stat -f '%z' "$operation/archives/$id.manifest")" \
                "$(sha256 -q "$operation/archives/$id.manifest")" >> "$case_dir/changed-request"
            mv "$operation/archives/$id.pkg" "$case_dir/$id.pkg"
        done
        install -m 0400 "$case_dir/changed-request" "$operation/request"
        awk -F '\t' -v digest="$(sha256 -q "$operation/request")" 'BEGIN {OFS=FS} $1=="request-sha256" {$2=digest} {print}' \
            "$operation/local-update.started" > "$case_dir/changed-start"
        install -m 0600 "$case_dir/changed-start" "$operation/local-update.started"
        ;;
    esac
    if [ -e "$case_dir/changed-actions" ]; then
        install -m 0600 "$case_dir/changed-actions" "$operation/actions"
    fi
    inside /tools/pkg -C /dev/null info -a -R > "$case_dir/manifests.before"
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_dir/installed.before"
    cp "$root/var/db/pkg/local.sqlite" "$case_dir/database.before.sqlite"
    cp "$root/probe/actions" "$case_dir/actions.before"
    case "$name" in
    missing-database|linked-database)
        mv "$root/var/db/pkg/local.sqlite" "$root/work/retained.sqlite"
        if [ "$name" = linked-database ]; then
            ln -s /work/retained.sqlite "$root/var/db/pkg/local.sqlite"
        fi
        ;;
    esac
    attempt=$operation/recovery.TEST0001
    mkdir -m 0700 "$attempt"
    invoke recover /tools/candidate -C /work/interrupted/config local-recover \
        /work/interrupted/request /work/interrupted/recovery.TEST0001
    if [ "$name" = recover ] || [ "$name" = prior-drift ]; then
        [ "$status" -eq 0 ]
        if [ "$name" = prior-drift ]; then
            grep -Fxq 'FreeBSD resolver: prior identity not retained from before: xcat-update-lib 9' "$case_dir/recover.stderr"
            [ "$(grep -c '^FreeBSD resolver: prior identity not retained from before:' "$case_dir/recover.stderr")" -eq 1 ]
            cmp "$attempt/managed.request" "$workspace/recover/root/work/interrupted/recovery.TEST0001/managed.request"
        fi
        grep -q '^scope[[:space:]]provenance-only$' "$attempt/local-recover.result"
        grep -q '^execution[[:space:]]uncertain$' "$attempt/local-recover.result"
        grep -q '^operation-scope[[:space:]]local-update$' "$attempt/local-recover.result"
        grep -q '^rejected-sha256[[:space:]]-$' "$attempt/local-recover.result"
        for binding in request:request prior-request:prior-request started:local-update.started \
            before:before actions:actions observed:observed managed-request:managed.request; do
            key=${binding%:*}
            file=${binding#*:}
            case "$key" in observed|managed-request) source=$attempt ;; *) source=$operation ;; esac
            expected=$(sha256 -q "$source/$file")
            observed=$(awk -F '\t' -v key="$key-sha256" '$1==key {n++; print $2} END {if(n!=1) exit 1}' \
                "$attempt/local-recover.result")
            [ "$observed" = "$expected" ]
        done
        [ "$(grep -c '^package' "$attempt/managed.request")" -eq 3 ]
        awk -F '\t' '$1=="package" && ($4=="xcat-update-app" || $4=="xcat-update-lib") {n++; if ($5!="2") exit 1} END {if (n!=2) exit 1}' "$attempt/managed.request"
        mkdir -m 0700 "$operation/recovery.CONTROL1"
        invoke old-control /tools/helper -C /work/interrupted/config local-recover \
            /work/interrupted/request /work/interrupted/recovery.CONTROL1
        [ "$status" -eq 1 ]
        grep -q 'invalid resolver arguments' "$case_dir/old-control.stderr"
        [ ! -e "$operation/recovery.CONTROL1/local-recover.result" ]
        mkdir -m 0700 "$operation/recovery.PARTIAL1"
        printf partial > "$operation/recovery.PARTIAL1/observed"
        invoke partial /tools/candidate -C /work/interrupted/config local-recover \
            /work/interrupted/request /work/interrupted/recovery.PARTIAL1
        [ "$status" -eq 1 ]
        grep -Fxq 'FreeBSD resolver: resolver root must be empty' "$case_dir/partial.stderr"
        [ ! -e "$operation/recovery.PARTIAL1/local-recover.result" ]
        [ "$(cat "$operation/recovery.PARTIAL1/observed")" = partial ]
        mkdir -m 0700 "$operation/recovery.RETRY001"
        invoke retry /tools/candidate -C /work/interrupted/config local-recover \
            /work/interrupted/request /work/interrupted/recovery.RETRY001
        [ "$status" -eq 0 ]
        cmp "$attempt/local-recover.result" "$operation/recovery.RETRY001/local-recover.result"
        cmp "$attempt/managed.request" "$operation/recovery.RETRY001/managed.request"
    else
        [ "$status" -eq 1 ]
        [ ! -e "$attempt/local-recover.result" ]
        case "$name" in
        missing-before|missing-start) diagnostic='cannot open local-check input' ;;
        invalid-start) diagnostic='interrupted package start differs from its request' ;;
        invalid-before) diagnostic='invalid retained installed package roster' ;;
        missing-package) diagnostic='recovery cannot adopt a missing installed package' ;;
        unexpected-package) diagnostic='recovery found an unauthorized installed identity' ;;
        metadata-drift|prior-flags) diagnostic='recovery installed metadata differs from retained inputs' ;;
        pending-trigger) diagnostic='deferred triggers remain after finalization' ;;
        missing-archive) diagnostic='invalid local-check archive roster' ;;
        altered-archive) diagnostic='local-check native archive checksum mismatch' ;;
        missing-database|linked-database) diagnostic='package recovery requires an existing protected database' ;;
        verify-scope) diagnostic='recovery cannot adopt changes from a verification operation' ;;
        rejected-operation) diagnostic='recovery cannot adopt changes from a rejected operation' ;;
        missing-actions|empty-actions|partial-actions|wrong-*|duplicate-action)
            diagnostic='recovery requires a complete matching action plan' ;;
        ambiguous-start) diagnostic='ambiguous interrupted package start' ;;
        manifest-update) diagnostic='recovery update requires archive inputs' ;;
        esac
        grep -Fxq "FreeBSD resolver: $diagnostic" "$case_dir/recover.stderr"
        case "$name" in
        verify-scope|rejected-operation|missing-actions|empty-actions|partial-actions|wrong-*|duplicate-action|manifest-update)
            mkdir -m 0700 "$operation/recovery.PREVIOUS"
            invoke previous /tools/previous -C /work/interrupted/config local-recover \
                /work/interrupted/request /work/interrupted/recovery.PREVIOUS
            [ "$status" -eq 0 ]
            grep -q '^complete[[:space:]]yes$' "$operation/recovery.PREVIOUS/local-recover.result"
            grep -q '^execution[[:space:]]uncertain$' "$operation/recovery.PREVIOUS/local-recover.result"
            awk -F '\t' '$1=="package" && ($4=="xcat-update-app" || $4=="xcat-update-lib") {n++; if($5!="2") exit 1} END {if(n!=2) exit 1}' \
                "$operation/recovery.PREVIOUS/managed.request"
            controls=$((controls+1))
            printf 'RECOVERY_PREVIOUS_CASE %s PASS\n' "$name"
            ;;
        esac
    fi
    case "$name" in
    missing-database|linked-database)
        grep -q 'package recovery requires an existing protected database' "$case_dir/recover.stderr"
        if [ "$name" = linked-database ]; then
            [ -L "$root/var/db/pkg/local.sqlite" ]
            [ "$(readlink "$root/var/db/pkg/local.sqlite")" = /work/retained.sqlite ]
            rm "$root/var/db/pkg/local.sqlite"
        else
            [ ! -e "$root/var/db/pkg/local.sqlite" ]
            [ ! -L "$root/var/db/pkg/local.sqlite" ]
        fi
        cmp "$root/work/retained.sqlite" "$case_dir/database.before.sqlite"
        mv "$root/work/retained.sqlite" "$root/var/db/pkg/local.sqlite"
        ;;
    esac
    # Native advisory locks update SQLite bookkeeping. Compare complete package
    # manifests and state; retain both databases for independent table readback.
    inside /tools/pkg -C /dev/null info -a -R > "$case_dir/manifests.after"
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_dir/installed.after"
    cp "$root/var/db/pkg/local.sqlite" "$case_dir/database.after.sqlite"
    cmp "$case_dir/manifests.before" "$case_dir/manifests.after"
    cmp "$case_dir/installed.before" "$case_dir/installed.after"
    cmp "$case_dir/actions.before" "$root/probe/actions"
    if [ "$name" = recover ]; then
        for label in empty-repeat same-version; do
            next=$root/work/recovered-$label
            mkdir -m 0700 "$next" "$next/cache" "$next/repos"
            cp -Rp "$root/work/$label/archives" "$next/archives"
            cp "$root/work/$label/request" "$next/request"
            cp "$attempt/managed.request" "$next/prior-request"
            sed "s|/work/$label/cache|/work/recovered-$label/cache|" \
                "$root/work/$label/config" > "$next/config"
            chmod 0400 "$next/request" "$next/prior-request" "$next/config"
            mode=local-verify
            [ "$label" != same-version ] || mode=local-update
            invoke "$label" /tools/candidate -C "/work/recovered-$label/config" \
                "$mode" "/work/recovered-$label/request" /
            [ "$status" -eq 0 ]
            grep -q '^changes[[:space:]]0$' "$next/$mode.result"
            grep -q '^actions[[:space:]]0$' "$next/$mode.result"
            cmp "$case_dir/actions.before" "$root/probe/actions"
        done
        mkdir -m 0700 "$next/recovery.LOSTACK1"
        invoke lost-ack /tools/candidate -C /work/recovered-same-version/config local-recover \
            /work/recovered-same-version/request /work/recovered-same-version/recovery.LOSTACK1
        [ "$status" -eq 0 ]
        grep -q '^execution[[:space:]]uncertain$' "$next/recovery.LOSTACK1/local-recover.result"
        cmp "$attempt/managed.request" "$next/recovery.LOSTACK1/managed.request"
        cmp "$case_dir/actions.before" "$root/probe/actions"
    fi
    umount "$active"
    active=
    count=$((count+1))
    printf 'RECOVERY_CASE %s PASS\n' "$name"
done
[ "$controls" -eq 11 ]
printf 'RECOVERY_PREVIOUS_COMPLETE %s\n' "$controls"
printf 'RECOVERY_CASES_COMPLETE %s\n' "$count"

#!/bin/sh

# Run on a disposable FreeBSD node. The reference is an unchanged native test
# root with anchor, outside, lib1 and app1 installed. The fixture catalogue has
# their archives, lib2/app2, and the added2-stop/lib2-stop interrupted archives.
# Arguments: workspace, candidate, reference, previous, previous SHA256, fixtures,
# the earlier relaxed recovery helper, and that helper's SHA256.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 8 ]
workspace=$1
helper=$2
reference=$3
previous=$4
previous_digest=$5
fixtures=$6
relaxed=$7
relaxed_digest=$8
for path in "$workspace" "$helper" "$reference" "$previous" "$fixtures" "$relaxed"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
done
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ]
[ ! -L "$workspace" ]
[ -x "$helper" ]
[ -x "$previous" ]
[ -x "$relaxed" ]
[ "${#previous_digest}" -eq 64 ]
case "$previous_digest" in *[!0-9a-f]*) exit 2 ;; esac
[ "$(sha256 -q "$previous")" = "$previous_digest" ]
[ "${#relaxed_digest}" -eq 64 ]
case "$relaxed_digest" in *[!0-9a-f]*) exit 2 ;; esac
[ "$(sha256 -q "$relaxed")" = "$relaxed_digest" ]
[ -f "$fixtures/catalogue" ]
mkdir -m 0700 "$workspace"
active=
finish()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ -n "$active" ]; then umount "$active" || result=1; fi
    printf '%s\n' "$result" > "$workspace/exit-code"
    exit "$result"
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
request()
{
    destination=$1
    shift
    : > "$destination.rows"
    index=0
    for key do
        awk -F '\t' -v key="$key" -v ordinal="$index" 'BEGIN {OFS="\t"}
            $1==key {if (NF!=7) exit 1; n++; print "package", "p" ordinal, "r1", $2, $3, $4, $5,
                "All/" key ".pkg", "applications/All/" key ".pkg", $6, $7, $7}
            END {if (n!=1) exit 1}' "$fixtures/catalogue" >> "$destination.rows"
        index=$((index+1))
    done
    printf 'format\txcat-freebsd-local-request-1\nplan\t%s\n' "$(sha256 -q "$destination.rows")" > "$destination"
    cat "$destination.rows" >> "$destination"
    rm "$destination.rows"
    chmod 0400 "$destination"
}
stage()
{
    operation_name=$1
    shift
    operation=$root/work/$operation_name
    mkdir -m 0700 "$operation" "$operation/cache" "$operation/repos" "$operation/archives"
    request "$operation/request" "$@"
    cp -p "$root/work/drift-prior" "$operation/prior-request"
    chmod 0400 "$operation/prior-request"
    sed "s|/work/interrupted/cache|/work/$operation_name/cache|" \
        "$reference/work/interrupted/config" > "$operation/config"
    chmod 0400 "$operation/config"
    index=0
    for key do
        install -m 0400 "$fixtures/archives/$key.pkg" "$operation/archives/p$index.pkg"
        index=$((index+1))
    done
    chmod 0500 "$operation/archives"
}
printf 'DRIFT_PREVIOUS_SHA256 %s\n' "$previous_digest"
printf 'DRIFT_RELAXED_SHA256 %s\n' "$relaxed_digest"
for name in removed-partial origin-partial removed-complete archive-priority verify-drift empty-drift \
    no-actions-drift rejected-drift re-add header-only; do
    case_dir=$workspace/$name
    root=$case_dir/root
    mkdir -m 0700 "$case_dir"
    mkdir -m 0755 "$root"
    sha256 "$reference/var/db/pkg/local.sqlite" "$reference/probe/actions" > "$case_dir/reference.before"
    cp -a "$reference/." "$root/"
    install -m 0555 "$helper" "$root/tools/candidate"
    install -m 0555 "$previous" "$root/tools/previous"
    install -m 0555 "$relaxed" "$root/tools/relaxed"
    [ "$(sha256 -q "$root/tools/previous")" = "$previous_digest" ]
    [ "$(sha256 -q "$root/tools/relaxed")" = "$relaxed_digest" ]
    active=$root/dev
    mount -t devfs devfs "$active"
    devfs -m "$active" rule apply hide
    for device in null zero random urandom; do devfs -m "$active" rule apply path "$device" unhide; done
    request "$root/work/drift-prior" anchor outside lib1 app1
    stage drift-establish anchor outside lib1 app1
    invoke establish /tools/previous -C /work/drift-establish/config local-verify /work/drift-establish/request /
    [ "$status" -eq 0 ]
    [ "$(grep -c '^package' "$operation/managed.request")" -eq 4 ]
    cp -p "$operation/managed.request" "$root/work/drift-prior"
    case "$name" in
    archive-priority)
        stage drift-history lib2 app2
        invoke history /tools/previous -C /work/drift-history/config local-update /work/drift-history/request /
        [ "$status" -eq 0 ]
        cp -p "$operation/managed.request" "$root/work/drift-prior"
        for key in lib1 app1; do
            invoke "downgrade-$key" /tools/pkg -C /work/setup.conf -R /work/repos add -q -f "/fixtures/$key.pkg"
            [ "$status" -eq 0 ]
        done
        ;;
    origin-partial)
        invoke drift /tools/pkg -C /work/setup.conf -R /work/repos set -y \
            -o misc/xcat-update-outside:misc/xcat-update-outside-drift xcat-update-outside
        [ "$status" -eq 0 ]
        inside /tools/pkg -C /dev/null query '%o' xcat-update-outside > "$case_dir/origin"
        grep -Fxq misc/xcat-update-outside-drift "$case_dir/origin"
        ;;
    re-add)
        invoke drift /tools/pkg -C /work/setup.conf -R /work/repos delete -y xcat-update-anchor
        [ "$status" -eq 0 ]
        ;;
    *)
        invoke unlock /tools/pkg -C /work/setup.conf -R /work/repos unlock -y xcat-update-outside
        [ "$status" -eq 0 ]
        invoke drift /tools/pkg -C /work/setup.conf -R /work/repos delete -y xcat-update-outside
        [ "$status" -eq 0 ]
        ;;
    esac
    scope=local-update
    expected=1
    case "$name" in
    removed-complete) stage drift-operation lib2 app2; expected=0 ;;
    archive-priority) stage drift-operation lib2-stop app2 ;;
    verify-drift) stage drift-operation anchor; scope=local-verify; expected=0 ;;
    no-actions-drift|header-only) stage drift-operation anchor; expected=0 ;;
    re-add) stage drift-operation repack; expected=0 ;;
    rejected-drift) stage drift-operation repack ;;
    empty-drift) stage drift-operation ;;
    *) stage drift-operation added2-stop ;;
    esac
    invoke operation /tools/previous -C /work/drift-operation/config "$scope" /work/drift-operation/request /
    [ "$status" -eq "$expected" ]
    if [ "$expected" -eq 0 ]; then
        [ -f "$operation/$scope.result" ]
    else
        [ ! -e "$operation/$scope.result" ]
    fi
    case "$name" in
    removed-partial|origin-partial)
        [ ! -e "$operation/$scope.rejected" ]
        grep -Fxq 'addition entry' "$root/probe/actions"
        ;;
    archive-priority)
        [ ! -e "$operation/$scope.rejected" ]
        grep -Fxq 'partial upgrade entry' "$root/probe/actions"
        ;;
    empty-drift)
        [ -f "$operation/$scope.rejected" ]
        grep -Fxq 'FreeBSD resolver: empty operation prior provenance differs from installed state' "$case_dir/operation.stderr"
        # Isolate the empty-request gate from rejection and missing actions.
        mv "$operation/$scope.rejected" "$case_dir/original-rejection"
        printf 'format\txcat-freebsd-update-actions-1\n' > "$operation/actions"
        chmod 0600 "$operation/actions"
        ;;
    no-actions-drift)
        # Retain the actual no-change records, then inject the durable prefix
        # left by a crash before actions. No package application took place.
        grep -q '^changes[[:space:]]0$' "$operation/local-update.result"
        [ ! -e "$operation/local-update.rejected" ]
        mkdir -m 0700 "$case_dir/original-records"
        for member in actions after managed.request local-update.result; do
            mv "$operation/$member" "$case_dir/original-records/$member"
        done
        ;;
    header-only)
        grep -q '^changes[[:space:]]0$' "$operation/local-update.result"
        printf 'format\txcat-freebsd-update-actions-1\n' | cmp - "$operation/actions"
        ;;
    rejected-drift)
        grep -q '^apply[[:space:]]not-started$' "$operation/local-update.rejected"
        # Exercise the rejection gate independently of the missing-actions gate.
        printf 'format\txcat-freebsd-update-actions-1\n' > "$operation/actions"
        chmod 0600 "$operation/actions"
        ;;
    esac
    inside /tools/pkg -C /dev/null info -a -R > "$case_dir/manifests.before"
    inside /tools/pkg -C /dev/null query -a '%n %v %o %a %k %t' > "$case_dir/installed.before"
    cp "$root/var/db/pkg/local.sqlite" "$case_dir/database.before.sqlite"
    cp "$root/probe/actions" "$case_dir/actions.before"
    for implementation in candidate previous relaxed; do
        case "$implementation" in
        candidate) attempt_name=CURRENT6 ;;
        previous) attempt_name=PREVIOUS ;;
        relaxed) attempt_name=RELAXED5 ;;
        esac
        attempt=$operation/recovery.$attempt_name
        mkdir -m 0700 "$attempt"
        invoke "$implementation" "/tools/$implementation" -C /work/drift-operation/config local-recover \
            /work/drift-operation/request "/work/drift-operation/recovery.$attempt_name"
        positive=yes
        case "$implementation:$name" in
        previous:*|candidate:empty-drift|candidate:no-actions-drift|candidate:rejected-drift|relaxed:verify-drift|relaxed:empty-drift)
            positive=no ;;
        esac
        notices=$(awk '/^FreeBSD resolver: prior identity not retained from before:/ {n++} END {print n+0}' "$case_dir/$implementation.stderr")
        if [ "$positive" = no ]; then
            [ "$status" -eq 1 ]
            grep -Fxq 'FreeBSD resolver: recovery prior request differs from its retained roster' "$case_dir/$implementation.stderr"
            [ "$notices" -eq 0 ]
            [ ! -e "$attempt/local-recover.result" ]
            continue
        fi
        [ "$status" -eq 0 ]
        grep -q '^execution[[:space:]]uncertain$' "$attempt/local-recover.result"
        grep -Fxq "$(printf 'operation-scope\t%s' "$scope")" "$attempt/local-recover.result"
        if [ "$name" = archive-priority ]; then
            requested=$(awk -F '\t' '$4=="xcat-update-lib" {print $11}' "$operation/request")
            prior=$(awk -F '\t' '$4=="xcat-update-lib" {print $11}' "$operation/prior-request")
            recovered=$(awk -F '\t' '$4=="xcat-update-lib" {print $11}' "$attempt/managed.request")
            [ -n "$requested" ]
            [ "$requested" = "$recovered" ]
            [ "$prior" != "$recovered" ]
            for member in "$operation/prior-request" "$attempt/managed.request"; do
                awk -F '\t' '$4=="xcat-update-lib" {n++; print $4,$5,$6,$7} END {if(n!=1) exit 1}' "$member"
            done > "$case_dir/$implementation.identities"
            [ "$(sort -u "$case_dir/$implementation.identities" | wc -l | tr -d ' ')" -eq 1 ]
            for package in xcat-update-lib xcat-update-app; do
                grep -Fxq "FreeBSD resolver: prior identity not retained from before: $package 2" "$case_dir/$implementation.stderr"
            done
            [ "$notices" -eq 2 ]
            [ "$(grep -c '^package' "$attempt/managed.request")" -eq 3 ]
            if grep -q xcat-update-app "$attempt/managed.request"; then exit 1; fi
        else
            drifted=xcat-update-outside
            [ "$name" != re-add ] || drifted=xcat-update-anchor
            grep -Fxq "FreeBSD resolver: prior identity not retained from before: $drifted 1" "$case_dir/$implementation.stderr"
            [ "$notices" -eq 1 ]
            if [ "$name" = re-add ]; then
                requested=$(awk -F '\t' '$4=="xcat-update-anchor" {print $11}' "$operation/request")
                prior=$(awk -F '\t' '$4=="xcat-update-anchor" {print $11}' "$operation/prior-request")
                recovered=$(awk -F '\t' '$4=="xcat-update-anchor" {print $11}' "$attempt/managed.request")
                [ -n "$requested" ] && [ "$requested" = "$recovered" ] && [ "$prior" != "$recovered" ]
                for member in "$operation/prior-request" "$attempt/managed.request"; do
                    awk -F '\t' '$4=="xcat-update-anchor" {n++; print $4,$5,$6,$7} END {if(n!=1) exit 1}' "$member"
                done > "$case_dir/$implementation.identities"
                [ "$(sort -u "$case_dir/$implementation.identities" | wc -l | tr -d ' ')" -eq 1 ]
            elif grep -q xcat-update-outside "$attempt/managed.request"; then
                exit 1
            fi
            count=4
            case "$name" in
            removed-complete|verify-drift|header-only|no-actions-drift|rejected-drift) count=3 ;;
            esac
            case "$name" in
            removed-complete|verify-drift|header-only|re-add)
                cmp "$operation/managed.request" "$attempt/managed.request"
                ;;
            esac
            [ "$(grep -c '^package' "$attempt/managed.request")" -eq "$count" ]
        fi
    done
    inside /tools/pkg -C /dev/null info -a -R > "$case_dir/manifests.after"
    inside /tools/pkg -C /dev/null query -a '%n %v %o %a %k %t' > "$case_dir/installed.after"
    cp "$root/var/db/pkg/local.sqlite" "$case_dir/database.after.sqlite"
    cmp "$case_dir/manifests.before" "$case_dir/manifests.after"
    cmp "$case_dir/installed.before" "$case_dir/installed.after"
    cmp "$case_dir/actions.before" "$root/probe/actions"
    umount "$active"
    active=
    sha256 "$reference/var/db/pkg/local.sqlite" "$reference/probe/actions" > "$case_dir/reference.after"
    cmp "$case_dir/reference.before" "$case_dir/reference.after"
    printf 'RECOVERY_DRIFT %s PASS\n' "$name"
done
printf 'RECOVERY_DRIFT_COMPLETE 10\n'

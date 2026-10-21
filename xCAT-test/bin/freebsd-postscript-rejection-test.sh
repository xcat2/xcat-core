#!/bin/sh

# Run inside a disposable copy of the qualified installed package state.
# The worker, backend, package database and package scripts remain real.
# Bundle plan records are fixtures; repository publication is tested separately.
# Boot changes use a test wrapper; actual reboot acceptance is separate.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 2 ]
workspace=$1
case_name=$2
case "$workspace" in /*) ;; *) exit 2 ;; esac
case "$workspace" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ "$(cat /input/disposable)" = xcat-freebsd-package-failure-test-1 ]
[ ! -e "$workspace" ]
mkdir -m 0700 "$workspace"
base=/var/db/xcat/postscripts
initial=/var/db/xcat/pkgbase-install
worker=/usr/local/libexec/xcat-postscript
fixtures=/input/fixtures
tab=$(printf '\t')
effects=$workspace/effects
: > "$effects"
initial_hash=$(sha256 -q "$initial/result")
node=$(awk -F '\t' '$1=="node" {print $2}' "$initial/result")
generation=$(awk -F '\t' '$1=="generation" {print $2}' "$initial/result")
attempt=$(awk -F '\t' '$1=="attempt" {print $2}' "$initial/result")
cp -p "$base/package-head" "$workspace/head-before"
restore=
time_restore=
database_mode=
finish()
{
    result=$?
    trap - EXIT
    if [ -n "$restore" ]; then mv "$restore" "$initial/result" || result=99; fi
    if [ -n "$time_restore" ]; then mv "$time_restore" "$worker-time" || result=99; fi
    if [ -n "$database_mode" ]; then chmod "$database_mode" /var/db/pkg || result=99; fi
    printf '%s\n' "$result" > "$workspace/exit-code"
    exit "$result"
}
trap finish EXIT

expect()
{
    if [ "$1" != "$2" ]; then
        printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
        exit 1
    fi
}

field()
{
    awk -F '\t' -v key="$2" '$1==key {if (NF!=2) exit 1; n++; value=$2}
        END {if (n!=1) exit 1; print value}' "$1"
}

invoke()
{
    label=$1
    shift
    operation_status=0
    "$worker" "$@" > "$workspace/$label.stdout" 2> "$workspace/$label.stderr" || operation_status=$?
    printf '%s\n' "$operation_status" > "$workspace/$label.status"
}

bundle()
{
    run=$(printf '%032x' "$1")
    bundle_dir=$base/incoming/$run
    mkdir -m 0700 "$bundle_dir" "$bundle_dir/tree" "$bundle_dir/archives"
    # Retain the source repository/target bindings and select fixture rows.
    awk -F '\t' 'BEGIN {OFS="\t"} $1=="format" {$2="xcat-freebsd-package-plan-2"}
        $1 !~ /^(package|component|application|scope)$/ {print}
        $1=="resolver-libraries" {print "scope", "applications"}' \
        /input/original.plan > "$bundle_dir/package.plan"
    package_index=0
    for key in $package_key; do
        awk -F '\t' -v key="$key" -v ordinal="$package_index" 'BEGIN {OFS="\t"}
            $1==key {if (NF!=7) exit 1; n++; print "application", $2;
                print "package", "p" ordinal, "r1", $2, $3, $4, $5,
                    "All/" key ".pkg", "applications/All/" key ".pkg", $6, $7, $7}
            END {if (n!=1) exit 1}' "$fixtures/catalogue" >> "$bundle_dir/package.plan"
        cp -p "$fixtures/archives/$key.pkg" "$bundle_dir/archives/p$package_index.pkg"
        chmod 0400 "$bundle_dir/archives/p$package_index.pkg"
        package_index=$((package_index+1))
    done
    chmod 0500 "$bundle_dir/archives"
    plan=$(sha256 -q "$bundle_dir/package.plan")
    printf 'format\txcat-freebsd-local-request-1\nplan\t%s\n' "$plan" > "$bundle_dir/request"
    awk -F '\t' '$1=="package" {print}' "$bundle_dir/package.plan" >> "$bundle_dir/request"
    for name in first second; do
        printf '#!/bin/sh\nprintf "%s\\n" >> "%s"\n' "$name" "$effects" > "$bundle_dir/tree/$name"
        chmod 0555 "$bundle_dir/tree/$name"
    done
    raw=$(sha256 -q -s first)
    printf '1\tpostscripts\t%s\t%s\tfirst\n2\tpostbootscripts\t%s\t%s\tsecond\n' \
        "$raw" "$(sha256 -q "$bundle_dir/tree/first")" "$(sha256 -q -s second)" \
        "$(sha256 -q "$bundle_dir/tree/second")" > "$bundle_dir/entries"
    framework_stop=:
    [ "$case_name" != framework-driver-error ] || framework_stop='exit 125'
    cat > "$bundle_dir/driver" <<EOF
#!/bin/sh
printf 'driver\n' >> '$effects'
'$worker' begin "\$1" 1 || exit 125
'$worker' execute "\$1" 1 first || exit 125
$framework_stop
'$worker' begin "\$1" 2 || exit 125
'$worker' execute "\$1" 2 second || exit 125
'$worker' driver-complete "\$1" 2 || exit 125
EOF
    mtree -c -K sha256digest -p "$bundle_dir/tree" > "$bundle_dir/tree.mtree"
    bundle_generation=$generation
    if [ "$case_name:$1" = preparation-wrong-generation:1 ]; then
        bundle_generation=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    fi
    kind=update
    format=xcat-freebsd-postscript-bundle-2
    if [ "$case_name" = boot-verify-drift ] || [ "${repeat_followup-no}" = yes ] ||
        { [ "${case_name#preapply-}" != "$case_name" ] && [ "$1" -gt 1 ]; }; then
        kind=repeat
        format=xcat-freebsd-postscript-bundle-3
    fi
    printf 'format\t%s\nrun\t%s\nnode\t%s\ngeneration\t%s\nattempt\t%s\nkind\t%s\npreparation\t%s\nsource\t%s\nplan\t%s\nrequest\t%s\npackage-mode\t%s\ndriver\t%s\nentries\t%s\ntree\t%s\nscripts\t2\nentry-timeout\t30\nrun-timeout\t120\nlog-limit\t65536\n' \
        "$format" "$run" "$node" "$bundle_generation" "$attempt" "$kind" "$raw" "$raw" "$plan" \
        "$(sha256 -q "$bundle_dir/request")" "$mode" "$(sha256 -q "$bundle_dir/driver")" \
        "$(sha256 -q "$bundle_dir/entries")" "$(sha256 -q "$bundle_dir/tree.mtree")" > "$bundle_dir/manifest"
    if [ "$kind" = repeat ]; then
        printf 'boot\t%s\n' "$(/usr/local/libexec/xcat-postscript-time boot)" >> "$bundle_dir/manifest"
    fi
    snapshot=$(sha256 -q "$bundle_dir/manifest")
    invoke "admit-$1" admit "$run" "$snapshot"
    expect "$operation_status" 0 'bundle admission'
    state=$base/runs/$run
}

recovery_fault()
{
    fault=${case_name#recovery-}
    fault_file=
    fault_snapshot=$snapshot
    fault_target=
    fault_after=no
    case "$fault" in
    prior) fault_file=$state/packages/prior-request; diagnostic='Recovery prior request differs from previous head' ;;
    request) fault_file=$state/packages/request; diagnostic='Recovery request differs from admitted run' ;;
    config) fault_file=$state/packages/config; diagnostic='Recovery configuration differs from admitted run' ;;
    head) fault_file=$base/package-head; diagnostic='Package head has advanced' ;;
    snapshot) fault_snapshot=$(printf '%064d' 1); diagnostic='Release snapshot differs' ;;
    helper) fault_file=/usr/local/libexec/freebsd-pkg-resolve; diagnostic='Native package helper differs' ;;
    native)
        mkdir -p /var/db/pkg/triggers
        chmod 0755 /var/db/pkg/triggers
        printf 'return 0\n' > /var/db/pkg/triggers/RecoveryPending
        diagnostic='Package recovery did not complete; retained attempt requires inspection'
        ;;
    capture|capture-status|receipt)
        cp -p "$worker-time" "$workspace/recovery-time-helper"
        cat > "$worker-time" <<EOF
#!/bin/sh
case "\$1:\$4" in
capture:*/recovery.*.stdout|capture-guard:*/recovery.*.stdout)
    [ '$fault' != capture ] || exit 1
    '$workspace/recovery-time-helper' "\$@" > '$workspace/recovery-native-capture' || exit 1
    if [ '$fault' = receipt ]; then
        for output in "\$@"; do :; done
        awk -F '\t' 'BEGIN {OFS="\t"} \$1=="scope" {\$2="installed"} {print}' \
            "\$output/local-recover.result" > "\$output/invalid.result"
        /bin/mv "\$output/invalid.result" "\$output/local-recover.result"
    fi
    awk -F '\t' 'BEGIN {OFS="\t"} \$1=="status" && "$fault"=="capture-status" {\$2=1} {print}' \
        '$workspace/recovery-native-capture'
    exit 0
    ;;
esac
exec '$workspace/recovery-time-helper' "\$@"
EOF
        chmod 0555 "$worker-time"
        case "$fault" in
        capture) diagnostic='Cannot capture command execution' ;;
        capture-status) diagnostic='Package recovery did not complete; retained attempt requires inspection' ;;
        receipt) diagnostic='Native package recovery binding differs' ;;
        esac
        ;;
    record|record-ack) fault_target=$state/packages.recovered; diagnostic='Cannot publish recovered package provenance' ;;
    run-head) fault_target=$state/package-head; diagnostic='Cannot retain recovered package head' ;;
    global-head|global-ack) fault_target=$base/package-head; diagnostic='Cannot publish recovered package head' ;;
    release|release-ack) fault_target=$state/released; diagnostic='Cannot publish release' ;;
    *) exit 2 ;;
    esac
    case "$fault" in *-ack) fault_after=yes ;; esac
    if [ -n "$fault_file" ]; then
        cp -p "$fault_file" "$workspace/recovery-original"
        printf '\ninvalid\n' >> "$fault_file"
    fi
    if [ -n "$fault_target" ]; then
        [ ! -e /sbin/mv ]
        cat > /sbin/mv <<EOF
#!/bin/sh
if [ "\$#" -eq 2 ] && [ "\$2" = '$fault_target' ]; then
    if [ '$fault_after' = yes ]; then
        /bin/mv "\$@" || exit 99
        /input/fsync-real "\$2" "\$(dirname "\$1")" "\$(dirname "\$2")" || exit 99
    fi
    printf '%s\n' '$fault' > '$workspace/publication-fault'
    exit 1
fi
exec /bin/mv "\$@"
EOF
        chmod 0555 /sbin/mv
    fi
    cp -p "$base/package-head" "$workspace/recovery-head-before"
    invoke recovery-failed release-after-reboot "$run" "$fault_snapshot"
    expect "$operation_status" 125 'failed recovery remains unreleased'
    grep -Fq "$diagnostic" "$workspace/recovery-failed.stderr"
    expect "$(cat "$base/active")" "$run" 'failed recovery retains the active run'
    [ ! -e "$state/result" ]
    [ ! -s "$effects" ]
    cmp /probe/actions "$workspace/actions.after"
    case "$fault" in
    global-ack|release|release-ack) expect "$(field "$base/package-head" run)" "$run" 'published recovery head is retained' ;;
    *) cmp "$workspace/recovery-head-before" "$base/package-head" ;;
    esac
    case "$fault" in
    release-ack) [ -f "$state/released" ] ;;
    *) [ ! -e "$state/released" ] ;;
    esac
    if [ -n "$fault_target" ]; then
        expect "$(cat "$workspace/publication-fault")" "$fault" 'publication fault was reached'
        rm /sbin/mv
    fi
    if [ -n "$fault_file" ]; then /bin/mv "$workspace/recovery-original" "$fault_file"; fi
    case "$fault" in
    native) rm /var/db/pkg/triggers/RecoveryPending ;;
    capture|capture-status|receipt) /bin/mv "$workspace/recovery-time-helper" "$worker-time" ;;
    esac
    find "$state/packages" -maxdepth 1 -type d -name 'recovery.*' > "$workspace/recovery-attempts.before"
    : > "$workspace/recovery-files.before"
    while IFS= read -r attempt_path; do
        find "$attempt_path" -type f | while IFS= read -r member; do
            printf '%s\t%s\n' "$(sha256 -q "$member")" "$member"
        done >> "$workspace/recovery-files.before"
    done < "$workspace/recovery-attempts.before"
}

lose_native_capture()
{
    cp -p "$worker-time" "$workspace/native-time"
    cat > "$worker-time" <<EOF
#!/bin/sh
case "\$1:\$4" in
capture:*/packages/stdout|capture-guard:*/packages/stdout)
    '$workspace/native-time' "\$@" > '$workspace/native.capture' || exit 1
    printf 'reached\n' > '$workspace/capture-fault'
    exit 1
    ;;
esac
exec '$workspace/native-time' "\$@"
EOF
    chmod 0555 "$worker-time"
}

prior_drift_result()
{
    rounds=1
    [ "$case_name" != prior-recovered-update ] || rounds=2
    round=1
    while [ "$round" -le "$rounds" ]; do
        expect "$run_status" 125 'unobserved native completion'
        expect "$(field "$workspace/native.capture" status)" 0 'native operation completed before capture fault'
        [ ! -e "$state/result" ]
        [ ! -e "$state/packages.result" ]
        [ ! -e "$state/packages.rejected" ]
        [ ! -s "$effects" ]
        [ -s "$state/packages/actions" ]
        [ ! -e "$state/packages/local-$mode.rejected" ]
        expect "$(field "$state/packages/local-$mode.result" complete)" yes 'original native result exists'
        if [ "$round" -eq 2 ]; then
            expect "$(field "$state/packages.previous" format)" xcat-freebsd-package-head-2 'previous head is recovered provenance'
        elif [ "$case_name" = prior-initial-update ]; then
            printf 'initial\t%s\n' "$initial_hash" > "$workspace/initial-anchor.expected"
            cmp "$workspace/initial-anchor.expected" "$state/packages.previous"
            [ ! -e "$base/package-head" ]
        fi
        mv "$workspace/native-time" "$worker-time"
        cp -p /probe/actions "$workspace/release-actions-$round"
        pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/release-roster-$round"
        invoke same-boot release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 125 'same-boot release remains refused'
        next_boot=$(printf '%s\n' "$snapshot:prior:$round" | sha256 -q)
        time_restore=$workspace/time-helper-$round
        mv "$worker-time" "$time_restore"
        cat > "$worker-time" <<EOF
#!/bin/sh
if [ "\$1" = boot ]; then printf '%s\n' '$next_boot'; exit 0; fi
exec '$time_restore' "\$@"
EOF
        chmod 0555 "$worker-time"
        invoke "released-$round" release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 0 'prior-drift changed-boot release'
        expect "$(field "$workspace/released-$round.stdout" outcome)" uncertain 'native completion does not certify script execution'
        expect "$(field "$workspace/released-$round.stdout" complete)" no 'released run remains incomplete'
        [ ! -e "$base/active" ]
        recovered=$state/packages/$(field "$state/packages.recovered" attempt)
        cmp "$state/packages/managed.request" "$recovered/managed.request"
        expect "$(field "$recovered/local-recover.result" operation-scope)" "local-$mode" 'recovery retains original scope'
        expect "$(field "$base/package-head" format)" xcat-freebsd-package-head-2 'recovery publishes a distinct head'
        awk -F '\t' '$1=="package" && $4=="xcat-update-app" {exit 1}' "$recovered/managed.request"
        notices=$(awk '/^FreeBSD resolver: prior identity not retained from before:/ {n++} END {print n+0}' "$recovered/stderr")
        expected_notices=0
        [ "$round" -ne 1 ] || expected_notices=1
        [ "$case_name" != prior-initial-update ] || expected_notices=2
        expect "$notices" "$expected_notices" 'exact prior-drift diagnostic count'
        if [ "$case_name" = prior-initial-update ]; then
            for name in app lib; do
                grep -Fxq "FreeBSD resolver: prior identity not retained from before: xcat-qualification-$name 1" "$recovered/stderr"
            done
            awk -F '\t' '$1=="package" && $4 ~ /^xcat-qualification-(app|lib)$/ {exit 1}' "$recovered/managed.request"
        elif [ "$round" -eq 1 ]; then
            grep -Fxq 'FreeBSD resolver: prior identity not retained from before: xcat-update-app 1' "$recovered/stderr"
        fi
        invoke "released-again-$round" release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 0 'recovery release retry'
        cmp "$workspace/released-$round.stdout" "$workspace/released-again-$round.stdout"
        cmp /probe/actions "$workspace/release-actions-$round"
        pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/release-roster-after-$round"
        cmp "$workspace/release-roster-$round" "$workspace/release-roster-after-$round"
        round=$((round+1))
        if [ "$round" -le "$rounds" ]; then
            mode=verify
            bundle "$round"
            lose_native_capture
            invoke run run "$run"
            run_status=$operation_status
        fi
    done
    mode=verify
    package_key=
    repeat_followup=yes
    bundle 3
    invoke followup run "$run"
    expect "$operation_status" 0 'repeat verification accepts recovered ownership'
    printf 'driver\nfirst\nsecond\n' > "$workspace/effects.expected"
    cmp "$workspace/effects.expected" "$effects"
    round=1
    while [ "$round" -le "$rounds" ]; do
        interrupted_run=$(printf '%032x' "$round")
        invoke "history-$round" evidence "$interrupted_run"
        expect "$operation_status" 0 'first recovery collection after later head advance'
        cp -p "$base/runs/$interrupted_run/evidence/archive.tar" "$workspace/evidence-$round.tar"
        tar -xOf "$workspace/evidence-$round.tar" interrupted.results > "$workspace/interrupted-results-$round"
        printf '1\tnot-run\t-\t-\t-\n2\tnot-run\t-\t-\t-\n' > "$workspace/interrupted-results.expected"
        cmp "$workspace/interrupted-results.expected" "$workspace/interrupted-results-$round"
        invoke "history-again-$round" evidence "$interrupted_run"
        expect "$operation_status" 0 'cached recovery collection'
        cmp "$workspace/history-$round.stdout" "$workspace/history-again-$round.stdout"
        round=$((round+1))
    done
    cmp /probe/actions "$workspace/release-actions-1"
    expect "$(sha256 -q "$initial/result")" "$initial_hash" 'initial installation receipt preserved'
}

preapply_result()
{
    expect "$run_status" 125 'unobserved native completion'
    [ ! -e "$state/result" ]
    [ ! -e "$state/packages.result" ]
    [ ! -e "$state/packages.rejected" ]
    [ ! -s "$effects" ]
    expect "$(cat "$workspace/capture-fault")" reached 'native capture fault was reached'
    cmp "$workspace/roster.before" "$workspace/roster.after"
    cmp /probe/actions "$workspace/actions.before"
    mv "$workspace/native-time" "$worker-time"
    mkdir -m 0700 "$workspace/original-records"
    for member in local-verify.started before actions after managed.request local-verify.result local-verify.rejected; do
        if [ -e "$state/packages/$member" ]; then cp -p "$state/packages/$member" "$workspace/original-records/$member"; fi
    done
    reason=no-actions
    case "$case_name" in
    preapply-start-initial)
        # This seed has a later managed head. Removing it exposes the older
        # installation request, which the native verifier correctly rejects.
        expect "$(field "$state/packages/local-verify.rejected" apply)" not-started 'initial-anchor rejection did not apply'
        expect "$(field "$workspace/native.capture" status)" 1 'initial-anchor drift is rejected'
        [ ! -e "$state/packages/actions" ]
        rm "$state/packages/before" "$state/packages/local-verify.rejected"
        ;;
    preapply-native-rejected|preapply-torn-rejected)
        expect "$(field "$state/packages/local-verify.rejected" apply)" not-started 'real native no-apply rejection'
        expect "$(field "$workspace/native.capture" status)" 1 'native rejection was observed only by the fault wrapper'
        # Header-only actions can precede a no-apply readback rejection. Inject
        # this durable prefix so the retained rejection authorizes release.
        printf 'format\txcat-freebsd-update-actions-1\n' > "$state/packages/actions"
        reason=native-rejected
        [ "$case_name" != preapply-torn-rejected ] || : > "$state/packages/local-verify.rejected"
        ;;
    *)
        expect "$(field "$state/packages/local-verify.result" changes)" 0 'native fixture applied no package changes'
        expect "$(field "$workspace/native.capture" status)" 0 'native no-change result preceded the injected fault'
        rm "$state/packages/local-verify.result" "$state/packages/after" "$state/packages/managed.request"
        if [ "$case_name" = preapply-torn-actions ]; then
            : > "$state/packages/actions"
            reason=recovered
        else
            rm "$state/packages/actions"
            case "$case_name" in
            preapply-start-only|preapply-start-initial) rm "$state/packages/before" ;;
            preapply-torn-start) printf 'torn\n' > "$state/packages/local-verify.started" ;;
            preapply-torn-before) printf 'torn\n' > "$state/packages/before" ;;
            *) exit 2 ;;
            esac
        fi
        ;;
    esac
    invoke same-boot release-after-reboot "$run" "$snapshot"
    expect "$operation_status" 125 'same-boot release remains refused'
    expect "$(cat "$base/active")" "$run" 'same-boot refusal retains the run'
    next_boot=$(printf '%s\n' "$snapshot:preapply" | sha256 -q)
    time_restore=$workspace/time-helper
    mv "$worker-time" "$time_restore"
    cat > "$worker-time" <<EOF
#!/bin/sh
if [ "\$1" = boot ]; then printf '%s\n' '$next_boot'; exit 0; fi
exec '$time_restore' "\$@"
EOF
    chmod 0555 "$worker-time"
    case "$case_name" in
    preapply-torn-actions|preapply-torn-rejected)
        invoke damaged release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 125 'ambiguous apply evidence refuses release'
        expect "$(cat "$base/active")" "$run" 'ambiguous evidence retains the active run'
        [ ! -e "$state/packages.preserved" ]
        [ ! -e "$state/packages.recovered" ]
        cmp "$workspace/head-before" "$base/package-head"
        member=actions
        [ "$case_name" != preapply-torn-rejected ] || member=local-verify.rejected
        cp -p "$workspace/original-records/$member" "$state/packages/$member"
        ;;
    esac
    invoke preserved release-after-reboot "$run" "$snapshot"
    expect "$operation_status" 0 'pre-apply changed-boot release'
    expect "$(field "$workspace/preserved.stdout" outcome)" uncertain 'original outcome remains uncertain'
    expect "$(field "$workspace/preserved.stdout" complete)" no 'original execution stays incomplete'
    [ ! -e "$base/active" ]
    [ ! -e "$state/result" ]
    if [ "$reason" = recovered ]; then
        expect "$(field "$state/packages.recovered" execution)" uncertain 'restored evidence permits provenance-only recovery'
    else
        preserved=$state/packages.preserved
        expect "$(field "$preserved" format)" xcat-freebsd-postscript-package-preserved-1 'preservation contract'
        expect "$(field "$preserved" reason)" "$reason" 'no-apply proof is retained'
        expect "$(field "$preserved" previous-sha256)" "$(sha256 -q "$state/packages.previous")" 'previous head binding'
        [ ! -e "$state/packages.recovered" ]
        [ ! -e "$state/package-head" ]
        if [ "$case_name" = preapply-start-initial ]; then
            [ ! -e "$base/package-head" ]
        else
            cmp "$workspace/head-before" "$base/package-head"
        fi
    fi
    invoke preserved-again release-after-reboot "$run" "$snapshot"
    expect "$operation_status" 0 'preservation release retry'
    cmp "$workspace/preserved.stdout" "$workspace/preserved-again.stdout"
    cmp /probe/actions "$workspace/actions.before"
    interrupted_run=$run
    interrupted_state=$state
    if [ -e "$workspace/package-database.before.tar" ]; then
        mv /var/db/pkg "$workspace/drifted-package-database"
        tar -xpf "$workspace/package-database.before.tar" -C /var/db
    fi
    if [ "$case_name" = preapply-start-initial ]; then
        # Restore the seed's verified later head before the repeat-run check.
        cp -p "$workspace/head-before" "$base/package-head"
    fi
    bundle 2
    expect "$(field "$state/bundle/manifest" kind)" repeat 'follow-up uses the real repeat contract'
    invoke followup run "$run"
    expect "$operation_status" 0 'new repeat run succeeds after release'
    printf 'driver\nfirst\nsecond\n' > "$workspace/effects.expected"
    cmp "$workspace/effects.expected" "$effects"
    # First collection occurs after a later run has advanced package-head.
    invoke history evidence "$interrupted_run"
    expect "$operation_status" 0 'first historical collection after head advance'
    cp -p "$interrupted_state/evidence/archive.tar" "$workspace/interrupted-evidence.tar"
    tar -xOf "$workspace/interrupted-evidence.tar" interrupted.results > "$workspace/interrupted-results"
    printf '1\tnot-run\t-\t-\t-\n2\tnot-run\t-\t-\t-\n' > "$workspace/interrupted-results.expected"
    cmp "$workspace/interrupted-results.expected" "$workspace/interrupted-results"
    if [ "$reason" != recovered ]; then
        tar -xOf "$workspace/interrupted-evidence.tar" packages.preserved > "$workspace/exported-preservation"
        cmp "$interrupted_state/packages.preserved" "$workspace/exported-preservation"
    fi
    invoke history-again evidence "$interrupted_run"
    expect "$operation_status" 0 'cached historical collection'
    cmp "$workspace/history.stdout" "$workspace/history-again.stdout"
    cmp /probe/actions "$workspace/actions.before"
    expect "$(sha256 -q "$initial/result")" "$initial_hash" 'initial installation receipt preserved'
}

package_key=
mode=verify
case "$case_name" in
success|preparation-missing-anchor|preparation-wrong-generation|preparation-database-*|verify-drift|boot-verify-drift|partial-head|preapply-*) ;;
update-pending-trigger) mode=update ;;
update-exit2) mode=update; package_key=exit2 ;;
update-exit3) mode=update; package_key=exit3 ;;
update-interrupt) mode=update; package_key=interrupt ;;
recovery-*) mode=update; package_key=interrupt ;;
prior-initial-update) mode=update; package_key=lib1 ;;
framework-driver-error) mode=update; package_key='lib1 app1' ;;
partial-upgrade|completed-torn|completed-head-torn|prior-drift-update|prior-drift-verify|prior-recovered-update) mode=update; package_key='lib1 app1' ;;
*) exit 2 ;;
esac
case "$case_name" in
partial-upgrade|completed-torn|completed-head-torn|prior-drift-update|prior-drift-verify|prior-recovered-update)
    bundle 16
    invoke setup run "$run"
    expect "$operation_status" 0 'initial managed package versions'
    : > "$effects"
    cp -p "$base/package-head" "$workspace/head-before"
    package_key='lib2 app2'
    [ "$case_name" != partial-upgrade ] || package_key='lib2-stop app2'
    case "$case_name" in
    prior-*)
        pkg-static -C /dev/null delete -y -f xcat-update-app > "$workspace/delete.stdout" 2> "$workspace/delete.stderr"
        package_key=lib2
        if [ "$case_name" = prior-drift-verify ]; then mode=verify; package_key=lib1; fi
        ;;
    esac
    ;;
esac
bundle 1
case "$case_name" in
preparation-missing-anchor)
    restore=$workspace/initial.result
    mv "$initial/result" "$restore"
    ;;
preparation-database-*)
    database_mode=$(stat -f '%Mp%Lp' /var/db/pkg)
    expect "$database_mode" 0755 'original database protection'
    case "$case_name" in
    preparation-database-mode) chmod 0700 /var/db/pkg ;;
    preparation-database-sticky) chmod 1755 /var/db/pkg ;;
    preparation-database-setgid) chmod 2755 /var/db/pkg ;;
    preparation-database-setuid) chmod 4755 /var/db/pkg ;;
    *) printf 'Unknown database protection case\n' >&2; exit 2 ;;
    esac
    stat -f '%u:%g:%Mp%Lp' /var/db/pkg > "$workspace/database-protection"
    ;;
verify-drift|boot-verify-drift|preapply-native-rejected|preapply-torn-rejected)
    tar -cpf "$workspace/package-database.before.tar" -C /var/db pkg
    pkg-static -C /dev/null delete -y -f xcat-qualification-app > "$workspace/delete.stdout" 2> "$workspace/delete.stderr"
    ;;
preapply-start-initial|prior-initial-update) rm "$base/package-head" ;;
update-pending-trigger)
    mkdir -p /var/db/pkg/triggers
    chmod 0755 /var/db/pkg/triggers
    printf 'return 0\n' > /var/db/pkg/triggers/Pending1
    ;;
partial-head)
    [ ! -e /sbin/fsync ]
    cat > /sbin/fsync <<'EOF'
#!/bin/sh
if [ "$*" = /var/db/xcat/postscripts/package-head.next ]; then
    /input/fsync-real "$@" || exit 99
    printf 'head stage synced\n' > /probe/head-stage
    exit 1
fi
exec /input/fsync-real "$@"
EOF
    chmod 0555 /sbin/fsync
    ;;
completed-torn|completed-head-torn)
    fault_pattern=$state/.packages.\*/result
    legacy_target=$state/packages.result
    if [ "$case_name" = completed-head-torn ]; then
        fault_pattern=$state/.package-head.\*/head
        legacy_target=$state/package-head
    fi
    [ ! -e /sbin/ln ]
    cat > /sbin/ln <<EOF
#!/bin/sh
case "\$2" in
'$legacy_target'|$fault_pattern)
    /bin/ln "\$@" || exit 99
    /input/fsync-real "\$2" "\$(dirname "\$2")" || exit 99
    printf '%s\n' '$case_name' > /probe/completion-fault
    exit 1
    ;;
esac
exec /bin/ln "\$@"
EOF
    chmod 0555 /sbin/ln
    ;;
esac
case "$case_name" in
prior-*) lose_native_capture ;;
preapply-*)
    cp -p "$worker-time" "$workspace/native-time"
    cat > "$worker-time" <<EOF
#!/bin/sh
case "\$1:\$4" in
capture:*/packages/stdout|capture-guard:*/packages/stdout)
    '$workspace/native-time' "\$@" > '$workspace/native.capture' || exit 1
    printf 'reached\n' > '$workspace/capture-fault'
    exit 1
    ;;
esac
exec '$workspace/native-time' "\$@"
EOF
    chmod 0555 "$worker-time"
    ;;
esac
pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/roster.before"
cp -p /probe/actions "$workspace/actions.before"
invoke run run "$run"
run_status=$operation_status
if [ -n "$restore" ]; then mv "$restore" "$initial/result"; restore=; fi
if [ -n "$database_mode" ]; then chmod "$database_mode" /var/db/pkg; database_mode=; fi
pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/roster.after"

case "$case_name" in
prior-*) prior_drift_result ;;
preapply-*) preapply_result ;;
framework-driver-error)
    expect "$run_status" 1 'observed framework failure is terminal'
    expect "$(field "$state/result" format)" xcat-freebsd-postscript-result-3 'framework failure result contract'
    expect "$(field "$state/result" outcome)" failed 'framework failure outcome'
    expect "$(field "$state/result" complete)" yes 'framework failure completion'
    expect "$(field "$state/packages/local-update.result" changes)" 2 'real package update completed'
    expect "$(field "$state/result" packages-sha256)" "$(sha256 -q "$state/packages.result")" 'completed package binding'
    [ ! -e "$base/active" ] && [ ! -e "$state/driver.complete" ]
    cmp "$state/package-head" "$base/package-head"
    cmp "$state/result" "$state/failure/content/result"
    printf 'driver\nfirst\n' > "$workspace/effects.expected"
    cmp "$workspace/effects.expected" "$effects"
    awk -F '\t' 'NR==1 {if($1!=1 || $2!="complete" || $3!=0) exit 1}
        NR==2 {if($1!=2 || $2!="not-run" || $3!="-") exit 1}
        END {if(NR!=2) exit 1}' "$state/failure/content/failure.results"
    [ -f "$state/packages.retired" ]
    expect "$(find "$state/bundle/archives" "$state/packages/archives" -type f | wc -l | tr -d ' ')" 0 'completed package payloads are retired'
    cp -p /probe/actions "$workspace/actions.after"
    invoke receipt receipt "$run"; expect "$operation_status" 0 'failed framework receipt'
    [ ! -s "$workspace/receipt.stderr" ]
    cmp "$state/result" "$workspace/receipt.stdout"
    invoke retry run "$run"; expect "$operation_status" 1 'cached framework failure'
    [ ! -s "$workspace/retry.stderr" ]
    cmp "$state/result" "$workspace/retry.stdout"
    invoke retire retire "$run"; expect "$operation_status" 0 'failure payload retirement retry'
    [ ! -s "$workspace/retire.stderr" ]
    cmp "$state/result" "$workspace/retire.stdout"
    invoke evidence evidence "$run"; expect "$operation_status" 0 'failed framework evidence'
    expect "$(field "$workspace/evidence.stdout" format)" xcat-freebsd-postscript-evidence-4 'failed framework evidence contract'
    cmp "$workspace/effects.expected" "$effects"
    cmp /probe/actions "$workspace/actions.after"
    pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/roster.retry"
    cmp "$workspace/roster.after" "$workspace/roster.retry"
    cp -p "$state/packages.retired" "$workspace/retirement.before"
    for damage in missing altered; do
        if [ "$damage" = missing ]; then
            damaged=framework.stderr
            mv "$state/failure/content/$damaged" "$workspace/held-snapshot"
        else
            damaged=failure.results
            cp -p "$state/failure/content/$damaged" "$workspace/held-snapshot"
            printf 'corrupt\n' >> "$state/failure/content/$damaged"
        fi
        printf '%s\n' "$run" > "$base/active"
        fsync "$base/active" "$base"
        for damaged_operation in receipt start run retire evidence; do
            label=$damage-$damaged_operation
            invoke "$label" "$damaged_operation" "$run"
            expect "$operation_status" 125 "damaged framework $label"
            [ ! -s "$workspace/$label.stdout" ]
            if [ "$damaged_operation" = retire ]; then
                grep -q 'Active package inputs must be retained' "$workspace/$label.stderr"
            else
                grep -q 'Framework failure snapshot is invalid' "$workspace/$label.stderr"
            fi
            expect "$(cat "$base/active")" "$run" 'damaged snapshot retains node ownership'
            cmp "$state/packages.retired" "$workspace/retirement.before"
            cmp "$workspace/effects.expected" "$effects"
            cmp /probe/actions "$workspace/actions.after"
        done
        mv "$base/active" "$workspace/held-active"
        invoke "$damage-retire-idle" retire "$run"
        expect "$operation_status" 125 'damaged framework retirement without active owner'
        [ ! -s "$workspace/$damage-retire-idle.stdout" ]
        grep -q 'Framework failure snapshot is invalid' "$workspace/$damage-retire-idle.stderr"
        cmp "$state/packages.retired" "$workspace/retirement.before"
        mv "$workspace/held-active" "$base/active"
        mv -f "$workspace/held-snapshot" "$state/failure/content/$damaged"
        invoke "$damage-restored" run "$run"
        expect "$operation_status" 1 'restored failed framework snapshot'
        [ ! -s "$workspace/$damage-restored.stderr" ]
        [ ! -e "$base/active" ]
        cmp "$state/result" "$workspace/$damage-restored.stdout"
    done
    ;;
success)
    expect "$run_status" 0 'successful prerequisite'
    expect "$(field "$state/result" outcome)" success 'successful run outcome'
    printf 'driver\nfirst\nsecond\n' > "$workspace/effects.expected"
    cmp "$workspace/effects.expected" "$effects"
    cmp "$workspace/roster.before" "$workspace/roster.after"
    [ ! -e "$base/active" ]
    ;;
update-exit2|update-exit3|update-interrupt|partial-head|partial-upgrade|completed-torn|completed-head-torn|recovery-*)
    expect "$run_status" 125 'uncertain operation status'
    [ ! -s "$effects" ]
    [ ! -e "$state/result" ]
    [ ! -e "$state/packages.rejected" ]
    [ ! -e "$state/packages/local-update.rejected" ]
    [ ! -e "$state/packages/local-verify.rejected" ]
    expect "$(cat "$base/active")" "$run" 'uncertain run remains active'
    cmp "$workspace/head-before" "$base/package-head"
    if [ "$case_name" = partial-head ]; then
        expect "$(cat /probe/head-stage)" 'head stage synced' 'real partial publication'
        [ -f "$state/packages.result" ]
        cmp "$state/package-head" "$base/package-head.next"
        cmp "$workspace/roster.before" "$workspace/roster.after"
    elif [ "$case_name" = completed-torn ] || [ "$case_name" = completed-head-torn ]; then
        expect "$(cat /probe/completion-fault)" "$case_name" 'completion publication fault was reached'
        expect "$(field "$state/packages/local-update.result" changes)" 2 'native upgrade completed before publication fault'
        rm /sbin/ln
    elif [ "$case_name" = partial-upgrade ]; then
        [ ! -e "$state/packages/local-update.result" ]
        grep -q '^xcat-update-lib 2 ' "$workspace/roster.after"
        grep -q '^xcat-update-app 1 ' "$workspace/roster.after"
        expect "$(grep -c '^partial upgrade entry$' /probe/actions)" 1 'upgrade stopped in the library script'
    else
        [ ! -e "$state/packages/local-update.result" ]
        grep -q "^$package_key entry$" /probe/actions
    fi
    cp -p /probe/actions "$workspace/actions.after"
    invoke retry start "$run"
    expect "$operation_status" 0 'uncertain observation'
    expect "$(field "$workspace/retry.stdout" outcome)" uncertain 'uncertain receipt'
    expect "$(field "$workspace/retry.stdout" complete)" no 'incomplete receipt'
    cmp /probe/actions "$workspace/actions.after"
    case "$case_name" in
    partial-head|recovery-*)
        if [ "$case_name" = partial-head ]; then
            invoke release release-after-reboot "$run" "$snapshot"
            expect "$operation_status" 125 'unfinished head publication refuses release'
            expect "$(cat "$base/active")" "$run" 'failed release keeps uncertainty'
        fi
        # These cases exercise recovery faults after the changed-boot boundary.
        next_boot=$(printf '%s\n' "$snapshot:interrupted" | sha256 -q)
        [ "$next_boot" != "$(field "$state/started" boot)" ]
        time_restore=$workspace/time-helper
        mv "$worker-time" "$time_restore"
        cat > "$worker-time" <<EOF
#!/bin/sh
if [ "\$1" = boot ]; then printf '%s\n' '$next_boot'; exit 0; fi
exec '$time_restore' "\$@"
EOF
        chmod 0555 "$worker-time"
        if [ "$case_name" = partial-head ]; then rm /sbin/fsync; fi
        case "$case_name" in recovery-*) recovery_fault ;; esac
        invoke changed-boot-release release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 0 'changed-boot release'
        release_receipt=$workspace/changed-boot-release.stdout
        ;;
    *)
        invoke observed-release release-after-reboot "$run" "$snapshot"
        expect "$operation_status" 0 'observed same-boot release'
        expect "$(field "$state/released" format)" xcat-freebsd-postscript-release-2 'observed release contract'
        expect "$(field "$state/released" boot)" "$(field "$state/started" boot)" 'release uses the actual original boot'
        release_receipt=$workspace/observed-release.stdout
        ;;
    esac
    expect "$(field "$release_receipt" outcome)" uncertain 'released run stays uncertain'
    expect "$(field "$release_receipt" complete)" no 'released run stays incomplete'
    [ ! -e "$base/active" ]
    [ ! -e "$state/result" ]
    case "$case_name" in
    recovery-*)
        while IFS="$tab" read -r expected member; do
            expect "$(sha256 -q "$member")" "$expected" 'earlier recovery evidence remains intact'
        done < "$workspace/recovery-files.before"
        while IFS= read -r attempt_path; do [ -d "$attempt_path" ]; done < "$workspace/recovery-attempts.before"
        ;;
    esac
    invoke release-again release-after-reboot "$run" "$snapshot"
    expect "$operation_status" 0 'release retry'
    cmp "$release_receipt" "$workspace/release-again.stdout"
    invoke interrupted-evidence evidence "$run"
    expect "$operation_status" 0 'interrupted evidence publication'
    expect "$(field "$workspace/interrupted-evidence.stdout" format)" xcat-freebsd-postscript-evidence-2 'interrupted evidence contract'
    cp -p "$state/evidence/archive.tar" "$workspace/interrupted-evidence.tar"
    tar -tf "$workspace/interrupted-evidence.tar" > "$workspace/interrupted-members"
    for stream in stdout stderr; do
        member=prerequisite.$stream
        found=$(awk -v name="$member" '$0==name {n++} END {print n+0}' "$workspace/interrupted-members")
        expect "$found" 1 "interrupted evidence contains $member"
        tar -xOf "$workspace/interrupted-evidence.tar" "$member" > "$workspace/retained-$member"
        cmp "$state/$member" "$workspace/retained-$member"
    done
    [ -s "$workspace/retained-prerequisite.stderr" ]
    printf '1\tnot-run\t-\t-\t-\n2\tnot-run\t-\t-\t-\n' > "$workspace/interrupted-results.expected"
    tar -xOf "$workspace/interrupted-evidence.tar" interrupted.results > "$workspace/interrupted-results"
    cmp "$workspace/interrupted-results.expected" "$workspace/interrupted-results"
    invoke interrupted-repeat evidence "$run"
    expect "$operation_status" 0 'retained interrupted evidence'
    cmp "$workspace/interrupted-evidence.stdout" "$workspace/interrupted-repeat.stdout"
    cmp "$workspace/interrupted-evidence.tar" "$state/evidence/archive.tar"
    cmp /probe/actions "$workspace/actions.after"
    [ ! -s "$effects" ]
    pkg-static -C /dev/null query -a '%n %v %a %k' > "$workspace/roster.released"
    cmp "$workspace/roster.after" "$workspace/roster.released"
    if [ "$case_name" = partial-head ] || [ "$case_name" = completed-head-torn ]; then
        cmp "$state/package-head" "$base/package-head"
    fi
    interrupted_run=$run
    interrupted_state=$state
    interrupted_key=$package_key
    interrupted_mode=$mode
    for next in 2 3; do
        mode=verify
        package_key=
        if [ "$next" -eq 3 ]; then mode=$interrupted_mode; package_key=$interrupted_key; fi
        bundle "$next"
        invoke "followup-$next" run "$run"
        expect "$operation_status" 0 'explicit follow-up after package recovery'
        expect "$(field "$state/result" outcome)" success 'follow-up completes'
        if [ "$case_name:$next" = partial-upgrade:3 ]; then
            expect "$(field "$state/packages/local-$mode.result" changes)" 1 'explicit update completes only the remaining upgrade'
            expect "$(field "$state/packages/local-$mode.result" actions)" 1 'only the remaining package has an action'
            expect "$(grep -c '^partial upgrade entry$' /probe/actions)" 1 'terminated library script is not replayed'
            expect "$(grep -c '^app 2$' /probe/actions)" 1 'application script runs once when requested'
            cp -p /probe/actions "$workspace/actions.after"
        else
            expect "$(field "$state/packages/local-$mode.result" changes)" 0 'follow-up changes no package'
            expect "$(field "$state/packages/local-$mode.result" actions)" 0 'follow-up applies no package action'
            cmp /probe/actions "$workspace/actions.after"
        fi
        printf 'driver\nfirst\nsecond\n' >> "$workspace/followup-effects.expected"
        cmp "$workspace/followup-effects.expected" "$effects"
    done
    if [ "$case_name" != partial-head ] && [ "$case_name" != completed-head-torn ]; then
        recovered=$interrupted_state/packages.recovered
        expect "$(field "$recovered" format)" xcat-freebsd-postscript-package-recovery-1 'recovered package contract'
        expect "$(field "$recovered" execution)" uncertain 'original execution remains uncertain'
        expect "$(field "$interrupted_state/package-head" format)" xcat-freebsd-package-head-2 'distinct recovered head'
        recovery=$interrupted_state/packages/$(field "$recovered" attempt)
        expect "$(field "$recovery/local-recover.result" scope)" provenance-only 'native recovery scope'
        expect "$(field "$recovery/local-recover.result" operation-scope)" local-update 'original native scope'
        expect "$(field "$recovery/capture" status)" 0 'observed native recovery exit'
        for binding in native:local-recover.result managed:managed.request capture:capture stdout:stdout stderr:stderr; do
            expect "$(field "$recovered" "${binding%:*}-sha256")" "$(sha256 -q "$recovery/${binding#*:}")" \
                'recovered evidence binding'
        done
        for member in packages.recovered packages/recovery.result packages/recovery.capture packages/recovery.stdout packages/recovery.stderr; do
            expect "$(awk -v name="$member" '$0==name {n++} END {print n+0}' "$workspace/interrupted-members")" 1 \
                'recovery evidence is exported'
        done
    fi
    invoke recovered-history evidence "$interrupted_run"
    expect "$operation_status" 0 'historical recovery evidence after later updates'
    cmp "$workspace/interrupted-evidence.stdout" "$workspace/recovered-history.stdout"
    cmp "$workspace/interrupted-evidence.tar" "$interrupted_state/evidence/archive.tar"
    invoke recovered-observation start "$interrupted_run"
    expect "$operation_status" 0 'historical interrupted observation'
    expect "$(field "$workspace/recovered-observation.stdout" outcome)" uncertain 'later updates do not complete the original run'
    cmp "$workspace/followup-effects.expected" "$effects"
    cmp /probe/actions "$workspace/actions.after"
    ;;
*)
    expect "$run_status" 1 'rejected operation status'
    [ ! -s "$effects" ]
    [ ! -e "$base/active" ]
    [ ! -e "$state/packages.result" ]
    [ ! -e "$state/driver.complete" ]
    expect "$(field "$state/result" format)" xcat-freebsd-postscript-result-2 'rejected result contract'
    expect "$(field "$state/result" outcome)" failed 'rejected outcome'
    expect "$(field "$state/result" complete)" yes 'complete rejection'
    printf '1\tnot-run\t-\t-\t-\n2\tnot-run\t-\t-\t-\n' > "$workspace/results.expected"
    cmp "$workspace/results.expected" "$state/results"
    cmp "$workspace/roster.before" "$workspace/roster.after"
    cmp /probe/actions "$workspace/actions.before"
    cmp "$workspace/head-before" "$base/package-head"
    expected_phase=native
    case "$case_name" in preparation-*) expected_phase=preparation ;; esac
    expect "$(field "$state/packages.rejected" phase)" "$expected_phase" 'rejection phase'
    [ -s "$state/prerequisite.stderr" ]
    cp -p "$state/prerequisite.stderr" "$workspace/diagnostic.before"
    invoke receipt receipt "$run"
    expect "$operation_status" 0 'rejection receipt'
    invoke replay run "$run"
    expect "$operation_status" 1 'rejected run replay'
    cmp "$workspace/receipt.stdout" "$workspace/replay.stdout"
    invoke evidence evidence "$run"
    expect "$operation_status" 0 'rejection evidence'
    expect "$(field "$workspace/evidence.stdout" format)" xcat-freebsd-postscript-evidence-3 'rejected evidence contract'
    cp -p "$state/evidence/archive.tar" "$workspace/rejected-evidence.tar"
    printf 'changed\n' >> "$state/prerequisite.stderr"
    invoke corrupt receipt "$run"
    expect "$operation_status" 125 'changed diagnostic rejected'
    cp -p "$workspace/diagnostic.before" "$state/prerequisite.stderr"
    invoke restored receipt "$run"
    expect "$operation_status" 0 'original rejection remains reportable'
    cmp "$workspace/receipt.stdout" "$workspace/restored.stdout"
    case "$case_name" in
    verify-drift|boot-verify-drift)
        mv /var/db/pkg "$workspace/rejected-package-database"
        tar -xpf "$workspace/package-database.before.tar" -C /var/db
        ;;
    update-pending-trigger) mv /var/db/pkg/triggers/Pending1 "$workspace/rejected-trigger" ;;
    esac
    rejected_run=$run
    rejected_state=$state
    bundle 2
    invoke recovered run "$run"
    expect "$operation_status" 0 'new same-boot operation'
    expect "$(field "$state/result" outcome)" success 'recovered outcome'
    expect "$(field "$state/started" boot)" "$(field "$rejected_state/started" boot)" 'same boot retained'
    expect "$(field "$base/package-head" run)" "$run" 'successful operation advances package-head'
    printf 'driver\nfirst\nsecond\n' > "$workspace/effects.expected"
    cmp "$workspace/effects.expected" "$effects"
    invoke historical evidence "$rejected_run"
    expect "$operation_status" 0 'historical rejection after head advance'
    cmp "$workspace/evidence.stdout" "$workspace/historical.stdout"
    cmp "$workspace/rejected-evidence.tar" "$rejected_state/evidence/archive.tar"
    invoke historical-replay start "$rejected_run"
    expect "$operation_status" 0 'historical failed run observation'
    cmp "$workspace/receipt.stdout" "$workspace/historical-replay.stdout"
    cmp "$workspace/effects.expected" "$effects"
    [ ! -e "$base/active" ]
    ;;
esac
expect "$(sha256 -q "$initial/result")" "$initial_hash" 'initial installation receipt preserved'
printf 'PASS %s\n' "$case_name"

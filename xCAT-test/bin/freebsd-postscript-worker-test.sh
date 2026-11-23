#!/bin/sh

# Run on a disposable FreeBSD 15.1 node with no installed postscript worker.
# The package boundary is a recorder; package acceptance is a separate test.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -ge 2 ] && [ "$#" -le 6 ]
workspace=$1
candidate=$2
adapters=${3:-}
selection=${4:-all}
timer=${5:-${candidate%/*}/xcat-postscript-time}
previous_worker=${6:-}
case "$workspace" in /*) ;; *) exit 2 ;; esac
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
base=/var/db/xcat/postscripts
worker=/usr/local/libexec/xcat-postscript
packages=$worker-packages
for path in "$workspace" "$base" "$worker" "$packages" "$worker-time" "$worker-time.real" /usr/sbin/daemon.real; do
    [ ! -e "$path" ]
    [ ! -L "$path" ]
done
/bin/sh -n "$candidate"
mkdir -m 0700 "$workspace"
mkdir -p /usr/local/libexec
install -m 0555 "$candidate" "$worker"
install -m 0555 "$timer" "$worker-time"
cp -p "$candidate" "$workspace/candidate"
cat > "$packages" <<'EOF'
package_inputs() { :; }
package_receipt() { :; }
package_commit() { :; }
package_retire() { :; }
package_status()
{
    [ ! -e /var/db/xcat/postscripts/package-not-ready ] || return 1
    printf 'recorder package status\n'
}
package_execute()
{
    [ ! -e /var/db/xcat/postscripts/block-packages ] || return 1
    printf 'plan\t%s\ncomplete\tyes\n' "$plan" > "$state/packages.result" || return 1
    fsync "$state/packages.result" "$state"
}
EOF
chmod 0444 "$packages"
cp -p "$packages" "$workspace/packages-recorder"
finish()
{
    result=$?
    for identity in "$workspace"/*/daemon.identity; do
        [ -f "$identity" ] || continue
        owned=${identity%/*}/owned.pid
        child_pid=$(cat "$owned")
        if "$worker-time" process "$child_pid" > "$workspace/daemon-observed" 2>/dev/null \
            && cmp -s "$identity" "$workspace/daemon-observed"; then
            kill -TERM "$child_pid" || result=1
        fi
    done
    printf '%s\n' "$result" > "$workspace/exit-code"
    [ ! -e "$workspace/fsync-wrapper" ] || rm -f /sbin/fsync
    [ ! -e "$workspace/mv-wrapper" ] || rm -f /sbin/mv
    [ ! -e "$workspace/lockf-wrapper" ] || rm -f /sbin/lockf
    [ ! -e "$worker-time.real" ] || mv -f "$worker-time.real" "$worker-time"
    [ ! -e /usr/sbin/daemon.real ] || mv -f /usr/sbin/daemon.real /usr/sbin/daemon
    # Failed state is retained at its original path for inspection.
    if [ "$result" -eq 0 ]; then rm "$worker" "$packages" "$worker-time"; fi
}
trap finish EXIT

invoke()
{
    label=$1
    shift
    status=0
    "$worker" "$@" > "$case_dir/$label.stdout" 2> "$case_dir/$label.stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/$label.status"
}

write_script()
{
    destination=$bundle/tree/$1
    shift
    printf '#!/bin/sh\n%s\n' "$*" > "$destination"
    chmod 0555 "$destination"
}

case_number=0
sync_cases=
[ -z "$adapters" ] || sync_cases='sync-success sync-failure sync-timeout sync-identity sync-duplicate sync-late sync-skip-update sync-skip-none sync-timezone'
if [ -n "${XCAT_FREEBSD_TEST_CLOCK_STEP-}" ]; then
    [ -n "$adapters" ] && [ -x "$XCAT_FREEBSD_TEST_CLOCK_STEP" ]
    sync_cases="$sync_cases sync-clock-forward sync-clock-backward"
fi
package_cases=
[ -z "$adapters" ] || package_cases='package-ospkgs package-otherpkgs package-options package-missing-context package-wrong-entry package-unready'
legacy_cases=
[ -z "$previous_worker" ] || legacy_cases=legacy-interrupted
for name in success many-arguments large-file exit3 signal exit143 timeout descendant descendant-inherited missing-interpreter \
    wrong-manifest changed-tree tree-owner tree-mode escaping-link package-failure \
    start-write-failure result-write-failure argument-write-failure log-limit stderr-limit log-exact stderr-exact log-timeout aggregate-output \
    concurrent start-busy start-unresolved start-tree-change start-handoff \
    interrupted boot-observation-failure boot-observation-invalid boot-release-failure boot-release-invalid \
    release-observed release-query-error release-observation-lost release-helper-mismatch \
    release-no-supervision release-original-zombie release-reused-pid supervisor-death \
    framework-driver-error framework-completion framework-publication framework-relock-busy framework-original-live \
    framework-snapshot-missing framework-snapshot-altered \
    start-publication receipt-completion partial-admission receipt-tamper completed-active receipt-output-failure \
    tree-exact-bound tree-over-bound tree-file-bound delivery-success delivery-short delivery-digest \
    delivery-symlink delivery-conflict delivery-invalid delivery-partial \
    evidence evidence-archive-tamper evidence-start-tamper evidence-finish-tamper evidence-publication $sync_cases $package_cases $legacy_cases; do
    case "$selection" in all|"$name") ;; *) continue ;; esac
    case_number=$((case_number+1))
    run=$(printf '%032x' "$case_number")
    case_dir=$workspace/$name
    mkdir -m 0700 "$case_dir" "$base" "$base/incoming" "$base/runs"
    bundle=$base/incoming/$run
    mkdir -m 0700 "$bundle" "$bundle/tree"
    effects=$case_dir/effects
    : > "$effects"
    write_script first "printf 'first\\n' >> '$effects'"
    write_script second "printf 'second\\n' >> '$effects'"
    entry_timeout=3
    run_timeout=20
    log_limit=4096
    entry_count=2
    case "$name" in
    aggregate-output)
        entry_timeout=10
        run_timeout=120
        log_limit=1048576
        entry_count=33
        write_script first "head -c 1048577 /dev/zero || exit 3
head -c 1048577 /dev/zero >&2 || exit 3
printf 'first\\n' >> '$effects'"
        ;;
    many-arguments) write_script first "[ \"\$#\" -eq 255 ] || exit 3
[ \"\$1\" = 0 ] || exit 3
shift 254
[ \"\$1\" = 254 ] || exit 3
printf 'first\\n' >> '$effects'" ;;
    large-file) write_script first "dd if=/dev/zero of='$case_dir/payload' bs=1048576 count=2 || exit 3
printf 'first\\n' >> '$effects'" ;;
    exit3) write_script first "printf 'first\\n' >> '$effects'; exit 3" ;;
    signal) write_script first "printf 'first\\n' >> '$effects'; kill -TERM \$\$" ;;
    exit143) write_script first "printf 'first\\n' >> '$effects'; exit 143" ;;
    timeout) write_script first "printf 'first\\n' >> '$effects'; sleep 30"; entry_timeout=1 ;;
    descendant|descendant-inherited)
        daemon_flag=-f
        [ "$name" != descendant-inherited ] || daemon_flag=
        write_script first "/usr/sbin/daemon $daemon_flag -p '$case_dir/daemon.pid' /bin/sleep 60
tries=0
while [ ! -s '$case_dir/daemon.pid' ]; do
    tries=\$((tries+1)); [ \"\$tries\" -lt 40 ] || exit 3; sleep 0.05
done
cp '$case_dir/daemon.pid' '$case_dir/owned.pid'
'$worker-time' process \"\$(cat '$case_dir/owned.pid')\" > '$case_dir/daemon.identity'
printf 'first\\n' >> '$effects'"
        ;;
    missing-interpreter) printf '#!/xcat-missing-interpreter\nexit 0\n' > "$bundle/tree/first" ;;
    escaping-link) ln -s /etc/passwd "$bundle/tree/escape" ;;
    result-write-failure) write_script first "printf 'first\\n' >> '$effects'; mkdir '$base/runs/$run/entries/1/result.tmp'" ;;
    log-limit) write_script first "printf 'first\\n' >> '$effects'; head -c 8192 /dev/zero" ;;
    stderr-limit) write_script first "printf 'first\\n' >> '$effects'; head -c 8192 /dev/zero >&2" ;;
    log-exact) write_script first "printf 'first\\n' >> '$effects'; head -c 4096 /dev/zero" ;;
    stderr-exact) write_script first "printf 'first\\n' >> '$effects'; head -c 4096 /dev/zero >&2" ;;
    log-timeout) write_script first "printf 'first\\n' >> '$effects'; yes bound"; entry_timeout=1 ;;
    concurrent|start-handoff|interrupted|legacy-interrupted|boot-observation-*|boot-release-*) write_script first "printf 'first\\n' >> '$effects'; sleep 2" ;;
    supervisor-death)
        entry_timeout=30
        run_timeout=60
        write_script first "printf 'first\\n' >> '$effects'
printf '%s\\n' \$\$ > '$case_dir/owned.pid'
'$worker-time' process \$\$ > '$case_dir/daemon.identity'
ps -o ppid= -p \$\$ | tr -d ' ' > '$case_dir/guard.pid'
'$worker-time' process \"\$(cat '$case_dir/guard.pid')\" > '$case_dir/guard.identity'
attempts=0
while [ ! -e '$case_dir/stop' ]; do
    attempts=\$((attempts+1)); [ \"\$attempts\" -lt 600 ] || exit 124
    sleep 0.05
done"
        ;;
    receipt-completion)
        entry_timeout=30
        write_script first "printf 'first\\n' >> '$effects'
attempts=0
while [ ! -e '$case_dir/worker-release' ]; do
    attempts=\$((attempts+1)); [ \"\$attempts\" -lt 30 ] || exit 124
    sleep 1
done"
        ;;
    evidence*) write_script first "printf 'first\\n' >> '$effects'; printf 'stdout\\n'; printf 'stderr\\n' >&2" ;;
    package-ospkgs|package-otherpkgs|package-options|package-missing-context|package-wrong-entry|package-unready)
        cp -p "$adapters/ospkgs" "$adapters/otherpkgs" "$adapters/xcatpackages.freebsd" "$bundle/tree/"
        package_script=ospkgs
        package_environment=
        package_arguments=
        case "$name" in
        package-otherpkgs) package_script=otherpkgs ;;
        package-options) package_arguments=--keeprepo ;;
        package-missing-context) package_environment='XCAT_FREEBSD_POSTSCRIPT_RUN=' ;;
        package-wrong-entry) package_environment='XCAT_FREEBSD_POSTSCRIPT_ENTRY=2' ;;
        package-unready) : > "$base/package-not-ready" ;;
        esac
        write_script first "printf 'first\\n' >> '$effects'
if (stat <&9) >/dev/null 2>&1; then exit 99; fi
exec env $package_environment ./$package_script $package_arguments"
        ;;
    sync-*)
        cp -p "$adapters/syncfiles" "$adapters/syncfiles.freebsd" "$bundle/tree/"
        entry_timeout=8
        sync_environment=
        sync_clock=
        case "$name" in
        sync-timeout|sync-late) entry_timeout=3 ;;
        sync-skip-update) sync_environment='UPDATENODE=1' ;;
        sync-skip-none) sync_environment='NOSYNCFILES=1' ;;
        sync-timezone) sync_environment='TZ=GMT+3' ;;
        sync-clock-forward) sync_clock="$XCAT_FREEBSD_TEST_CLOCK_STEP 300" ;;
        sync-clock-backward) sync_clock="$XCAT_FREEBSD_TEST_CLOCK_STEP -300" ;;
        esac
        write_script first "printf 'first\\n' >> '$effects'
if (stat <&9) >/dev/null 2>&1; then exit 99; fi
exec env $sync_environment $sync_clock ./syncfiles"
        ;;
    esac
    if [ "$name" = start-handoff ]; then
        write_script first "if (stat <&7) >/dev/null 2>&1 || (stat <&8) >/dev/null 2>&1 || (stat <&9) >/dev/null 2>&1; then exit 99; fi
printf 'first\\n' >> '$effects'; sleep 2"
    fi
    case "$name" in
    tree-exact-bound|tree-over-bound)
        remaining=$((67108864-$(stat -f %z "$bundle/tree/first")-$(stat -f %z "$bundle/tree/second")))
        for part in 1 2 3; do
            truncate -s 16777216 "$bundle/tree/bound-$part"
            remaining=$((remaining-16777216))
        done
        [ "$name" != tree-over-bound ] || remaining=$((remaining+1))
        truncate -s "$remaining" "$bundle/tree/bound-4"
        ;;
    tree-file-bound) truncate -s 16777217 "$bundle/tree/oversized" ;;
    esac
    raw=$(sha256 -q -s 'first "two words" ""')
    printf '1\tpostscripts\t%s\t%s\tfirst\n2\tpostbootscripts\t%s\t%s\tsecond\n' \
        "$raw" "$(sha256 -q "$bundle/tree/first")" "$raw" "$(sha256 -q "$bundle/tree/second")" > "$bundle/entries"
    if [ "$name" = aggregate-output ]; then
        : > "$bundle/entries"
        ordinal=1
        while [ "$ordinal" -le 33 ]; do
            printf '%s\tpostscripts\t%s\t%s\tfirst\n' "$ordinal" "$raw" "$(sha256 -q "$bundle/tree/first")" >> "$bundle/entries"
            ordinal=$((ordinal+1))
        done
    fi
    cat > "$bundle/driver" <<EOF
#!/bin/sh
printf 'before\\n' >> '$effects'
'$worker' begin "\$1" 1 || exit 125
'$worker' execute "\$1" 1 first "two words" "" || exit 125
'$worker' begin "\$1" 2 || exit 125
'$worker' execute "\$1" 2 second || exit 125
'$worker' driver-complete "\$1" 2 || exit 125
printf 'after\\n' >> '$effects'
EOF
    if [ "$name" = aggregate-output ]; then
        cat > "$bundle/driver" <<EOF
#!/bin/sh
ordinal=1
while [ "\$ordinal" -le 33 ]; do
    '$worker' begin "\$1" "\$ordinal" || exit 125
    '$worker' execute "\$1" "\$ordinal" first || exit 125
    ordinal=\$((ordinal+1))
done
'$worker' driver-complete "\$1" 33
EOF
    fi
    case "$name" in
    release-*|framework-*)
        cat > "$bundle/driver" <<EOF
#!/bin/sh
printf 'before\\n' >> '$effects'
'$worker' begin "\$1" 1 || exit 125
'$worker' execute "\$1" 1 first "two words" "" || exit 125
printf 'framework-fixture-failure\\n' >&2
exit 7
EOF
        if [ "$name" = framework-completion ]; then
            sed 's/^exit 7$/exit 0/' "$bundle/driver" > "$case_dir/completion-driver"
            cp "$case_dir/completion-driver" "$bundle/driver"
        fi
        ;;
    esac
    cp "$bundle/driver" "$case_dir/driver"
    if [ "$name" = many-arguments ]; then
        sed "/execute .* 1 first/c\\
set -- \"\$1\" 1 first; i=0; while [ \"\$i\" -lt 255 ]; do set -- \"\$@\" \"\$i\"; i=\$((i+1)); done; '$worker' execute \"\$@\" || exit 125
" "$bundle/driver" > "$case_dir/many-arguments-driver"
        cp "$case_dir/many-arguments-driver" "$bundle/driver"
    fi
    if [ "$name" = argument-write-failure ]; then
        sed "/execute .* 1 first/i\\
mkdir '$base/runs/$run/entries/1/argv.tmp'
" "$bundle/driver" > "$case_dir/argument-driver"
        cp "$case_dir/argument-driver" "$bundle/driver"
    fi
    mtree -c -K sha256digest -p "$bundle/tree" > "$bundle/tree.mtree"
    printf 'recorder package plan\n' > "$bundle/package.plan"
    printf 'recorder package request\n' > "$bundle/request"
    printf 'format\txcat-freebsd-postscript-bundle-2\nrun\t%s\nnode\tworker-test\ngeneration\t%s\nattempt\t%s\nkind\tfirstboot\npreparation\t%s\nsource\t%s\nplan\t%s\nrequest\t%s\npackage-mode\tverify\ndriver\t%s\nentries\t%s\ntree\t%s\nscripts\t%s\nentry-timeout\t%s\nrun-timeout\t%s\nlog-limit\t%s\n' \
        "$run" "$run" "$run" "$raw" "$raw" "$(sha256 -q "$bundle/package.plan")" \
        "$(sha256 -q "$bundle/request")" "$(sha256 -q "$bundle/driver")" \
        "$(sha256 -q "$bundle/entries")" "$(sha256 -q "$bundle/tree.mtree")" "$entry_count" "$entry_timeout" "$run_timeout" "$log_limit" > "$bundle/manifest"
    snapshot=$(sha256 -q "$bundle/manifest")
    case "$name" in
    wrong-manifest) printf 'extra\tvalue\n' >> "$bundle/manifest" ;;
    changed-tree) printf '# changed\n' >> "$bundle/tree/first" ;;
    tree-owner) chown 65534 "$bundle/tree/second" ;;
    tree-mode) chmod 0577 "$bundle/tree/second" ;;
    partial-admission)
        mkdir -m 0700 "$base/runs/$run"
        mv "$bundle" "$base/runs/$run/bundle"
        printf '%s\n' "$snapshot" > "$base/runs/$run/snapshot.tmp"
        ln "$base/runs/$run/snapshot.tmp" "$base/runs/$run/snapshot"
        ;;
    esac
    case "$name" in
    delivery-*)
        mv "$bundle" "$case_dir/export"
        tar --format=pax -cpf "$case_dir/bundle.tar" -C "$case_dir/export" .
        if [ "$name" = delivery-invalid ]; then
            printf 'not an archive\n' > "$case_dir/bundle.tar"
            truncate -s 10240 "$case_dir/bundle.tar"
        fi
        archive_digest=$(sha256 -q "$case_dir/bundle.tar")
        archive_bytes=$(stat -f %z "$case_dir/bundle.tar")
        invoke delivery delivery "$run" "$snapshot" "$archive_digest" "$archive_bytes"
        [ "$status" -eq 0 ]
        [ "$(awk -F '\t' '$1=="state" {print $2}' "$case_dir/delivery.stdout")" = upload ]
        upload=$base/incoming/$run.delivery/bundle.tar
        [ "$(awk -F '\t' '$1=="path" {print $2}' "$case_dir/delivery.stdout")" = "$upload" ]
        if [ "$name" = delivery-conflict ]; then
            cp "$base/incoming/$run.delivery/request" "$case_dir/request-before"
            wrong=$(sha256 -q -s different)
            invoke conflict delivery "$run" "$snapshot" "$wrong" "$archive_bytes"
            [ "$status" -eq 125 ]
            cmp "$base/incoming/$run.delivery/request" "$case_dir/request-before"
        fi
        if [ "$name" = delivery-symlink ]; then
            ln -s "$case_dir/bundle.tar" "$upload"
        else
            cp "$case_dir/bundle.tar" "$upload"
            case "$name" in
            delivery-short) truncate -s "$((archive_bytes-512))" "$upload" ;;
            delivery-digest) printf x | dd of="$upload" bs=1 seek="$((archive_bytes-1))" conv=notrunc 2>/dev/null ;;
            esac
        fi
        if [ "$name" = delivery-partial ]; then
            mkdir -m 0700 "$base/runs/$run"
            mv "$case_dir/export" "$base/runs/$run/bundle"
            printf '%s\n' "$snapshot" > "$base/runs/$run/snapshot.tmp"
            ln "$base/runs/$run/snapshot.tmp" "$base/runs/$run/snapshot"
        fi
        invoke receive receive "$run" "$snapshot" "$archive_digest" "$archive_bytes"
        case "$name" in
        delivery-short|delivery-digest|delivery-symlink)
            [ "$status" -eq 125 ]
            [ ! -s "$effects" ]
            [ ! -e "$base/runs/$run/snapshot" ]
            rm "$upload"
            cp "$case_dir/bundle.tar" "$upload"
            invoke repaired receive "$run" "$snapshot" "$archive_digest" "$archive_bytes"
            ;;
        esac
        ;;
    *) invoke admit admit "$run" "$snapshot" ;;
    esac
    case "$name" in
    missing-interpreter|wrong-manifest|changed-tree|tree-owner|tree-mode|escaping-link|tree-over-bound|tree-file-bound|delivery-invalid)
        [ "$status" -eq 125 ]
        [ ! -s "$effects" ]
        ;;
    *)
        [ "$status" -eq 0 ]
        state=$base/runs/$run
        if [ "$name" = legacy-interrupted ]; then
            install -m 0555 "$previous_worker" "$worker"
            cp -p "$previous_worker" "$case_dir/previous-worker"
        fi
        case "$name" in
        package-failure) : > "$base/block-packages" ;;
        start-write-failure) mkdir "$state/started.tmp" ;;
        esac
        case "$name" in
        framework-relock-busy|framework-original-live)
            [ ! -e /sbin/lockf ]
            [ ! -L /sbin/lockf ]
            framework_capture=$state/captures/$(printf 'framework.stdout\n' | sha256 -q)
            cat > "$workspace/lockf-wrapper" <<EOF
#!/bin/sh
if [ -f '$framework_capture/finished' ] && [ ! -e '$case_dir/reached' ]; then
    : > '$case_dir/reached'
    attempts=0
    while [ ! -e '$case_dir/locked' ]; do
        attempts=\$((attempts+1)); [ "\$attempts" -lt 200 ] || exit 124
        sleep 0.05
    done
fi
exec /usr/bin/lockf "\$@"
EOF
            install -m 0555 "$workspace/lockf-wrapper" /sbin/lockf
            ;;
        framework-publication)
            [ ! -e /sbin/mv ]
            [ ! -L /sbin/mv ]
            cat > "$workspace/mv-wrapper" <<EOF
#!/bin/sh
if [ "\$#" -eq 2 ] && [ "\$1" = '$state/failure/terminal' ] && [ "\$2" = '$state/result' ]; then
    printf 'injected failure receipt publication error\\n' >&2
    : > '$case_dir/reached'
    exit 1
fi
exec /bin/mv "\$@"
EOF
            install -m 0555 "$workspace/mv-wrapper" /sbin/mv
            ;;
        release-*)
            framework_capture=$state/captures/$(printf 'framework.stdout\n' | sha256 -q)
            [ ! -e /sbin/fsync ]
            [ ! -L /sbin/fsync ]
            cat > "$workspace/fsync-wrapper" <<EOF
#!/bin/sh
/usr/bin/fsync "\$@" || exit 1
if [ "\$#" -eq 1 ] && [ "\$1" = '$framework_capture' ] && [ -f '$framework_capture/finished' ] &&
    [ ! -e '$framework_capture/finished.tmp' ] && [ ! -e '$case_dir/reached' ]; then
    : > '$case_dir/reached'
    original=\$(awk -F '\t' '\$1 == "pid" {print \$2}' '$state/started')
    '$worker-time.real' process "\$original" > '$case_dir/original.identity' || exit 1
    kill -KILL "\$original" || exit 1
fi
EOF
            install -m 0555 "$workspace/fsync-wrapper" /sbin/fsync
            mv "$worker-time" "$worker-time.real"
            cat > "$workspace/time-wrapper" <<EOF
#!/bin/sh
if [ "\$1" = process-state ] && [ -e '$case_dir/query-error' ]; then
    printf 'injected process query error\\n' >&2
    exit 1
fi
if [ "\$1" = process-state ] && [ -f '$case_dir/process-observation' ]; then
    cat '$case_dir/process-observation'
    exit 0
fi
exec '$worker-time.real' "\$@"
EOF
            install -m 0555 "$workspace/time-wrapper" "$worker-time"
            ;;
        esac
        if [ "$name" = framework-original-live ]; then
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while [ ! -e "$case_dir/reached" ]; do
                tries=$((tries+1)); [ "$tries" -lt 200 ]; sleep 0.05
            done
            invoke refused release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 125 ]
            grep -q 'Original worker is still running' "$case_dir/refused.stderr"
            [ ! -e "$state/released" ]
            [ ! -e "$state/result" ]
            [ "$(cat "$base/active")" = "$run" ]
            : > "$case_dir/locked"
            status=0
            wait "$worker_pid" || status=$?
            printf '%s\n' "$status" > "$case_dir/run.status"
            rm /sbin/lockf
        elif [ "$name" = framework-relock-busy ]; then
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while [ ! -e "$case_dir/reached" ]; do
                tries=$((tries+1)); [ "$tries" -lt 200 ]; sleep 0.05
            done
            /usr/bin/lockf -k -t 0 "$base/lock" /bin/sh -c '
                : > "$1/locked"
                attempts=0
                while [ ! -e "$1/unlock" ]; do
                    attempts=$((attempts+1)); [ "$attempts" -lt 200 ] || exit 124
                    sleep 0.05
                done
            ' xcat "$case_dir" &
            holder_pid=$!
            status=0
            wait "$worker_pid" || status=$?
            printf '%s\n' "$status" > "$case_dir/run.status"
            : > "$case_dir/unlock"
            wait "$holder_pid"
            rm /sbin/lockf
        elif [ "$name" = start-busy ]; then
            lockf -k -t 0 "$base/lock" /bin/sh -c '
                : > "$1/locked"
                attempts=0
                while [ ! -e "$1/unlock" ]; do
                    attempts=$((attempts+1)); [ "$attempts" -lt 30 ] || exit 124
                    sleep 1
                done
            ' xcat "$case_dir" &
            holder_pid=$!
            tries=0
            while [ ! -e "$case_dir/locked" ] && [ "$tries" -lt 10 ]; do sleep 1; tries=$((tries+1)); done
            [ -e "$case_dir/locked" ]
            printf 'format\txcat-freebsd-postscript-status-3\nrun\t%s\nsnapshot\t%s\noutcome\tbusy\ncomplete\tno\n' \
                "$run" "$snapshot" > "$case_dir/expected-busy"
            for busy_operation in delivery receive; do
                invoke "$busy_operation-busy" "$busy_operation" "$run" "$snapshot" "$raw" 1024
                [ ! -e "$base/incoming/$run.delivery" ]
            done
            invoke run start "$run"
            sleep 1
            : > "$case_dir/unlock"
            wait "$holder_pid"
        elif [ "$name" = start-unresolved ]; then
            printf '%032d\n' 99 > "$base/active"
            invoke run start "$run"
        elif [ "$name" = start-tree-change ]; then
            cp -p "$state/bundle/tree/first" "$case_dir/original-first"
            printf '# changed after admission\n' >> "$state/bundle/tree/first"
            invoke run start "$run"
        elif [ "$name" = start-handoff ]; then
            [ ! -e /usr/sbin/daemon.real ]
            mv /usr/sbin/daemon /usr/sbin/daemon.real
            cat > /usr/sbin/daemon <<EOF
#!/bin/sh
: > '$case_dir/launch-reached'
attempts=0
while [ ! -e '$case_dir/launch-release' ]; do
    attempts=\$((attempts+1)); [ "\$attempts" -lt 30 ] || exit 124
    sleep 1
done
exec /usr/sbin/daemon.real "\$@"
EOF
            chmod 0555 /usr/sbin/daemon
            "$worker" start "$run" > "$case_dir/start.stdout" 2> "$case_dir/start.stderr" &
            starter_pid=$!
            tries=0
            while [ ! -e "$case_dir/launch-reached" ] && [ "$tries" -lt 10 ]; do sleep 1; tries=$((tries+1)); done
            [ -e "$case_dir/launch-reached" ]
            handoff_status=0
            lockf -s -k -t 0 "$base/lock" /bin/sh -c : || handoff_status=$?
            printf '%s\n' "$handoff_status" > "$case_dir/handoff.status"
            : > "$case_dir/launch-release"
            start_status=0
            wait "$starter_pid" || start_status=$?
            printf '%s\n' "$start_status" > "$case_dir/start.status"
            mv /usr/sbin/daemon.real /usr/sbin/daemon
            tries=0
            while [ ! -e "$state/result" ] && [ "$tries" -lt 20 ]; do sleep 1; tries=$((tries+1)); done
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            invoke run run "$run"
            [ "$handoff_status" -eq 75 ]
            [ "$start_status" -eq 0 ]
        elif [ -n "$sync_cases" ] && [ "${name#sync-}" != "$name" ] && [ "${name#sync-skip-}" = "$name" ]; then
            invoke inactive-sync sync-files "$run" 1
            [ "$status" -eq 125 ]
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while [ ! -e "$state/entries/1/sync.request" ] && [ "$tries" -lt 10 ]; do sleep 1; tries=$((tries+1)); done
            [ -e "$state/entries/1/sync.request" ]
            invoke waiting receipt "$run"; [ "$status" -eq 0 ]
            [ "$(awk -F '\t' '$1=="sync-ordinal" {print $2}' "$case_dir/waiting.stdout")" = 1 ]
            ! grep -q '^second$' "$effects"
            sync_result=0
            [ "$name" != sync-failure ] || sync_result=1
            evidence_digest=$(sha256 -q -s controller-result)
            if [ "$name" = sync-identity ]; then
                invoke wrong-snapshot sync-result "$run" "$raw" 1 0 "$evidence_digest"; [ "$status" -eq 125 ]
                invoke wrong-entry sync-result "$run" "$snapshot" 2 0 "$evidence_digest"; [ "$status" -eq 125 ]
                invoke wrong-status sync-result "$run" "$snapshot" 1 2 "$evidence_digest"; [ "$status" -eq 125 ]
                [ ! -e "$state/entries/1/sync.result" ]
            fi
            case "$name" in
            sync-timeout|sync-late) ;;
            *) invoke acknowledged sync-result "$run" "$snapshot" 1 "$sync_result" "$evidence_digest"; [ "$status" -eq 0 ] ;;
            esac
            status=0
            wait "$worker_pid" || status=$?
            printf '%s\n' "$status" > "$case_dir/run.status"
        elif [ "$name" = start-publication ]; then
            [ ! -e /sbin/fsync ] && [ ! -L /sbin/fsync ]
            cat > "$workspace/fsync-wrapper" <<EOF
#!/bin/sh
if [ "\$#" -eq 1 ] && [ "\$1" = '$state' ] && [ -d '$state/entries' ] && [ ! -e '$case_dir/reached' ]; then
    : > '$case_dir/reached'
    attempts=0
    while [ ! -e '$case_dir/release' ]; do
        attempts=\$((attempts+1)); [ "\$attempts" -lt 60 ] || exit 124
        sleep 1
    done
fi
exec /usr/bin/fsync "\$@"
EOF
            install -m 0555 "$workspace/fsync-wrapper" /sbin/fsync
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while [ ! -e "$case_dir/reached" ] && [ "$tries" -lt 20 ]; do sleep 1; tries=$((tries+1)); done
            [ -e "$case_dir/reached" ]
            invoke publication receipt "$run"
            observation_status=$status
            : > "$case_dir/release"
            status=0
            wait "$worker_pid" || status=$?
            printf '%s\n' "$status" > "$case_dir/run.status"
            rm /sbin/fsync
            [ "$observation_status" -eq 0 ]
            [ "$(awk -F '\t' '$1=="outcome" {print $2}' "$case_dir/publication.stdout")" = pending ]
        elif [ "$name" = receipt-completion ]; then
            mv "$worker-time" "$worker-time.real"
            cat > "$workspace/time-wrapper" <<EOF
#!/bin/sh
if [ "\${XCAT_TEST_RECEIPT_GATE-}" = '$case_dir' ] && [ "\$1" = process ]; then
    : > '$case_dir/reached'
    attempts=0
    while [ ! -e '$case_dir/release' ]; do
        attempts=\$((attempts+1)); [ "\$attempts" -lt 60 ] || exit 124
        sleep 1
    done
fi
exec '$worker-time.real' "\$@"
EOF
            install -m 0555 "$workspace/time-wrapper" "$worker-time"
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while ! grep -q '^first$' "$effects" && [ "$tries" -lt 10 ]; do sleep 1; tries=$((tries+1)); done
            grep -q '^first$' "$effects"
            env XCAT_TEST_RECEIPT_GATE="$case_dir" "$worker" receipt "$run" > "$case_dir/completion.stdout" 2> "$case_dir/completion.stderr" &
            observer_pid=$!
            tries=0
            while [ ! -e "$case_dir/reached" ] && [ "$tries" -lt 20 ]; do sleep 1; tries=$((tries+1)); done
            [ -e "$case_dir/reached" ]
            : > "$case_dir/worker-release"
            status=0
            wait "$worker_pid" || status=$?
            printf '%s\n' "$status" > "$case_dir/run.status"
            [ -f "$state/result" ]
            : > "$case_dir/release"
            wait "$observer_pid"
            mv -f "$worker-time.real" "$worker-time"
            cmp "$case_dir/completion.stdout" "$state/result"
            [ ! -s "$case_dir/completion.stderr" ]
        elif [ "$name" = concurrent ]; then
            invoke start start "$run"; [ "$status" -eq 0 ]
            invoke repeat-start start "$run"; [ "$status" -eq 0 ]
            tries=0
            while [ ! -e "$state/result" ] && [ "$tries" -lt 20 ]; do sleep 1; tries=$((tries+1)); done
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            invoke run run "$run"
        elif [ "$name" = supervisor-death ]; then
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while [ ! -s "$case_dir/guard.identity" ]; do
                tries=$((tries+1)); [ "$tries" -lt 100 ]; sleep 0.05
            done
            [ "$(awk -F '\t' '$1=="pid" {print $2}' "$state/started")" = "$worker_pid" ]
            "$worker-time" process "$worker_pid" > "$case_dir/worker.identity"
            [ "$(sha256 -q -s "$(cat "$case_dir/worker.identity")")" = "$(awk -F '\t' '$1=="process" {print $2}' "$state/started")" ]
            kill -KILL "$worker_pid"
            wait "$worker_pid" || :
            invoke busy-release release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 75 ]
            [ ! -e "$state/released" ]
            guard_pid=$(cat "$case_dir/guard.pid")
            "$worker-time" process "$guard_pid" > "$case_dir/guard.observed"
            cmp "$case_dir/guard.identity" "$case_dir/guard.observed"
            kill -KILL "$guard_pid"
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            invoke run run "$run"
        elif [ "$name" = interrupted ] || [ "$name" = legacy-interrupted ] ||
            [ "${name#boot-observation-}" != "$name" ] || [ "${name#boot-release-}" != "$name" ]; then
            "$worker" run "$run" > "$case_dir/run.stdout" 2> "$case_dir/run.stderr" &
            worker_pid=$!
            tries=0
            while ! grep -q '^first$' "$effects" && [ "$tries" -lt 10 ]; do sleep 1; tries=$((tries+1)); done
            grep -q '^first$' "$effects"
            invoke pending receipt "$run"
            grep -q 'pending' "$case_dir/pending.stdout"
            kill -KILL "$worker_pid"
            wait "$worker_pid" || :
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            [ "$name" != legacy-interrupted ] || install -m 0555 "$candidate" "$worker"
            invoke run run "$run"
        else
            invoke run run "$run"
        fi
        case "$name" in
        supervisor-death)
            [ "$status" -eq 125 ]
            owned_pid=$(cat "$case_dir/owned.pid")
            "$worker-time" process "$owned_pid" > "$case_dir/child.observed"
            cmp "$case_dir/daemon.identity" "$case_dir/child.observed"
            invoke refused release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 125 ]
            grep -q 'unobserved commands' "$case_dir/refused.stderr"
            [ ! -e "$state/result" ]
            [ ! -e "$state/released" ]
            [ "$(cat "$base/active")" = "$run" ]
            "$worker-time" process "$owned_pid" > "$case_dir/child.after"
            cmp "$case_dir/daemon.identity" "$case_dir/child.after"
            printf 'before\nfirst\n' > "$case_dir/expected-effects"
            cmp "$effects" "$case_dir/expected-effects"
            kill -TERM "$owned_pid"
            tries=0
            while "$worker-time" process "$owned_pid" > "$case_dir/child.exit" 2>/dev/null &&
                cmp -s "$case_dir/daemon.identity" "$case_dir/child.exit"; do
                tries=$((tries+1)); [ "$tries" -lt 100 ]; sleep 0.05
            done
            ;;
        framework-snapshot-missing|framework-snapshot-altered)
            [ "$status" -eq 1 ]
            [ ! -s "$case_dir/run.stderr" ]
            [ ! -e "$base/active" ]
            cp "$effects" "$case_dir/effects-before-retry"
            case "$name" in
            framework-snapshot-missing)
                damaged=framework.stderr
                mv "$state/failure/content/$damaged" "$case_dir/held-snapshot"
                ;;
            framework-snapshot-altered)
                damaged=failure.results
                cp -p "$state/failure/content/$damaged" "$case_dir/held-snapshot"
                printf 'corrupt\n' >> "$state/failure/content/$damaged"
                ;;
            esac
            printf '%s\n' "$run" > "$base/active"
            fsync "$base/active" "$base"
            # Native package integration checks the retirement boundary.
            for damaged_operation in receipt start run evidence; do
                invoke "damaged-$damaged_operation" "$damaged_operation" "$run"
                [ "$status" -eq 125 ]
                [ ! -s "$case_dir/damaged-$damaged_operation.stdout" ]
                grep -q 'Framework failure snapshot is invalid' "$case_dir/damaged-$damaged_operation.stderr"
                [ "$(cat "$base/active")" = "$run" ]
                cmp "$effects" "$case_dir/effects-before-retry"
            done
            mv -f "$case_dir/held-snapshot" "$state/failure/content/$damaged"
            invoke restored run "$run"
            [ "$status" -eq 1 ]
            [ ! -s "$case_dir/restored.stderr" ]
            [ ! -e "$base/active" ]
            invoke receipt receipt "$run"
            [ "$status" -eq 0 ]
            [ ! -s "$case_dir/receipt.stderr" ]
            cmp "$state/result" "$case_dir/receipt.stdout"
            cmp "$effects" "$case_dir/effects-before-retry"
            ;;
        framework-relock-busy)
            [ "$status" -eq 75 ]
            [ ! -e "$state/result" ]
            [ "$(cat "$base/active")" = "$run" ]
            grep -q 'Node is busy; retry run' "$state/supervisor.stderr"
            cp "$effects" "$case_dir/effects-before-retry"
            invoke released release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 0 ]
            invoke report evidence "$run"
            [ "$status" -eq 0 ]
            tar -xOf "$state/evidence/archive.tar" supervisor.stderr > "$case_dir/relock-diagnostic"
            grep -q 'Node is busy; retry run' "$case_dir/relock-diagnostic"
            cmp "$effects" "$case_dir/effects-before-retry"
            ;;
        framework-driver-error|framework-completion|framework-original-live|result-write-failure|argument-write-failure)
            [ "$status" -eq 1 ]
            [ ! -e "$base/active" ]
            grep -qx 'format.xcat-freebsd-postscript-result-3' "$state/result"
            grep -qx 'outcome.failed' "$state/result"
            grep -qx 'complete.yes' "$state/result"
            cp "$effects" "$case_dir/effects-before-retry"
            invoke receipt receipt "$run"
            [ "$status" -eq 0 ]
            [ ! -s "$case_dir/receipt.stderr" ]
            invoke retry run "$run"
            [ "$status" -eq 1 ]
            [ ! -s "$case_dir/retry.stderr" ]
            cmp "$case_dir/receipt.stdout" "$case_dir/retry.stdout"
            cmp "$effects" "$case_dir/effects-before-retry"
            invoke report evidence "$run"
            [ "$status" -eq 0 ]
            grep -qx 'format.xcat-freebsd-postscript-evidence-4' "$case_dir/report.stdout"
            tar -xOf "$state/evidence/archive.tar" failure.results > "$case_dir/dispositions"
            tar -xOf "$state/evidence/archive.tar" framework.stderr > "$case_dir/diagnostic"
            [ -s "$case_dir/diagnostic" ]
            grep -qx '2.not-run.-.-.-' "$case_dir/dispositions"
            case "$name" in
            framework-*) grep -q '^1.complete.0.' "$case_dir/dispositions" ;;
            *) grep -q '^1.uncertain.-.' "$case_dir/dispositions" ;;
            esac
            invoke report-again evidence "$run"
            [ "$status" -eq 0 ]
            cmp "$case_dir/report.stdout" "$case_dir/report-again.stdout"
            cmp "$effects" "$case_dir/effects-before-retry"
            ;;
        framework-publication)
            [ "$status" -eq 125 ]
            rm /sbin/mv
            [ -e "$case_dir/reached" ]
            [ -f "$state/failure/content/result" ]
            [ ! -e "$state/result" ]
            [ ! -e "$state/evidence" ]
            cp "$effects" "$case_dir/effects-before-retry"
            invoke observed receipt "$run"
            [ "$status" -eq 0 ]
            grep -qx 'outcome.uncertain' "$case_dir/observed.stdout"
            invoke released release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 0 ]
            invoke report evidence "$run"
            [ "$status" -eq 0 ]
            grep -qx 'format.xcat-freebsd-postscript-evidence-2' "$case_dir/report.stdout"
            tar -xOf "$state/evidence/archive.tar" supervisor.stderr > "$case_dir/publication-diagnostic"
            grep -q 'Cannot publish framework failure receipt' "$case_dir/publication-diagnostic"
            cmp "$effects" "$case_dir/effects-before-retry"
            ;;
        release-*)
            [ "$status" -ne 0 ]
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            rm /sbin/fsync
            [ ! -e "$state/result" ]
            printf 'before\nfirst\n' > "$case_dir/expected-effects"
            cmp "$effects" "$case_dir/expected-effects"
            invoke observed receipt "$run"
            [ "$status" -eq 0 ]
            grep -q '^outcome.*uncertain$' "$case_dir/observed.stdout"
            case "$name" in
            release-query-error) : > "$case_dir/query-error" ;;
            release-observation-lost) mv "$framework_capture/finished" "$case_dir/held-observation" ;;
            release-helper-mismatch)
                cp -p "$worker-time" "$case_dir/held-helper"
                printf '\n' >> "$worker-time"
                ;;
            release-no-supervision) mv "$state/supervision" "$case_dir/held-supervision" ;;
            release-original-zombie|release-reused-pid)
                original_identity=$(cat "$case_dir/original.identity")
                original_pid=${original_identity%%:*}
                query_state=zombie
                query_identity=$original_identity
                if [ "$name" = release-reused-pid ]; then
                    query_state=running
                    query_identity=$original_pid:1.000000
                    [ "$query_identity" != "$original_identity" ]
                fi
                printf 'format\txcat-freebsd-process-state-1\npid\t%s\nstate\t%s\nidentity\t%s\n' \
                    "$original_pid" "$query_state" "$query_identity" > "$case_dir/process-observation"
                ;;
            esac
            case "$name" in
            release-observed|release-original-zombie|release-reused-pid) ;;
            *)
                invoke refused release-after-reboot "$run" "$snapshot"
                [ "$status" -eq 125 ]
                [ ! -e "$state/released" ]
                [ "$(cat "$base/active")" = "$run" ]
                cmp "$effects" "$case_dir/expected-effects"
                case "$name" in
                release-query-error) rm "$case_dir/query-error" ;;
                release-observation-lost) mv "$case_dir/held-observation" "$framework_capture/finished" ;;
                release-helper-mismatch)
                    grep -q 'Run supervision helper differs; release requires a new boot' "$case_dir/refused.stderr"
                    mv -f "$case_dir/held-helper" "$worker-time"
                    ;;
                release-no-supervision)
                    grep -q 'Interrupted worker requires a new boot before release' "$case_dir/refused.stderr"
                    mv "$case_dir/held-supervision" "$state/supervision"
                    ;;
                esac
                ;;
            esac
            invoke released release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 0 ]
            grep -qx 'format.xcat-freebsd-postscript-release-2' "$state/released"
            [ "$(awk -F '\t' '$1=="boot" {print $2}' "$state/started")" = "$(awk -F '\t' '$1=="boot" {print $2}' "$state/released")" ]
            [ ! -e "$base/active" ]
            invoke reported evidence "$run"
            [ "$status" -eq 0 ]
            tar -xOf "$state/evidence/archive.tar" framework.stderr > "$case_dir/retained-diagnostic"
            grep -q 'Driver execution is incomplete' "$case_dir/retained-diagnostic"
            tar -xOf "$state/evidence/archive.tar" interrupted.results > "$case_dir/retained-entries"
            grep -q '^1.complete.0.' "$case_dir/retained-entries"
            grep -qx '2.not-run.-.-.-' "$case_dir/retained-entries"
            invoke released-again release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 0 ]
            cmp "$case_dir/released.stdout" "$case_dir/released-again.stdout"
            invoke report-again evidence "$run"
            [ "$status" -eq 0 ]
            cmp "$case_dir/reported.stdout" "$case_dir/report-again.stdout"
            cmp "$effects" "$case_dir/expected-effects"
            mv "$worker-time.real" "$worker-time"
            ;;
        start-busy|start-unresolved|start-tree-change)
            if [ "$name" = start-busy ]; then
                [ "$status" -eq 0 ]
                cmp "$case_dir/expected-busy" "$case_dir/run.stdout"
                [ ! -s "$case_dir/run.stderr" ]
                for busy_operation in delivery receive; do
                    [ "$(cat "$case_dir/$busy_operation-busy.status")" -eq 0 ]
                    cmp "$case_dir/expected-busy" "$case_dir/$busy_operation-busy.stdout"
                    [ ! -s "$case_dir/$busy_operation-busy.stderr" ]
                done
            else
                [ "$status" -eq 125 ]
                [ -s "$case_dir/run.stderr" ]
                [ ! -s "$case_dir/run.stdout" ]
            fi
            [ ! -s "$effects" ]
            [ ! -e "$state/started" ]
            [ ! -e "$state/entries" ]
            case "$name" in
            start-unresolved) mv "$base/active" "$case_dir/unresolved-active" ;;
            start-tree-change) cp -p "$case_dir/original-first" "$state/bundle/tree/first" ;;
            esac
            invoke recovered-start start "$run"
            [ "$status" -eq 0 ]
            tries=0
            while [ ! -e "$state/result" ] && [ "$tries" -lt 20 ]; do sleep 1; tries=$((tries+1)); done
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            invoke recovered-receipt receipt "$run"
            [ "$status" -eq 0 ]
            grep -q '^outcome.*success$' "$case_dir/recovered-receipt.stdout"
            printf 'before\nfirst\nsecond\nafter\n' > "$case_dir/expected-effects"
            cmp "$effects" "$case_dir/expected-effects"
            invoke completed-start start "$run"
            [ "$status" -eq 0 ]
            cmp "$case_dir/recovered-receipt.stdout" "$case_dir/completed-start.stdout"
            cmp "$effects" "$case_dir/expected-effects"
            ;;
        aggregate-output)
            [ "$status" -eq 0 ]
            [ ! -e "$base/active" ]
            [ "$(wc -l < "$effects" | tr -d ' ')" = 33 ]
            total=0
            ordinal=1
            while [ "$ordinal" -le 33 ]; do
                result=$state/entries/$ordinal/result
                [ "$(awk -F '\t' '$1 == "status" {print $2}' "$result")" = 0 ]
                [ "$(awk -F '\t' '$1 == "log-limit" {print $2}' "$result")" = 1016800 ]
                for stream in stdout stderr; do
                    bytes=$(stat -f %z "$state/entries/$ordinal/$stream")
                    [ "$bytes" = 1016800 ]
                    [ "$(awk -F '\t' -v key="$stream-truncated" '$1 == key {print $2}' "$result")" = yes ]
                    total=$((total+bytes))
                done
                ordinal=$((ordinal+1))
            done
            [ "$total" = 67108800 ]
            printf '%s\n' "$total" > "$case_dir/retained-output-bytes"
            cp "$effects" "$case_dir/effects-before-retry"
            invoke receipt receipt "$run"
            [ "$status" -eq 0 ]
            invoke retry run "$run"
            [ "$status" -eq 0 ]
            cmp "$effects" "$case_dir/effects-before-retry"
            cmp "$case_dir/receipt.stdout" "$case_dir/retry.stdout"
            invoke aggregate-evidence evidence "$run"
            [ "$status" -eq 0 ]
            ;;
        legacy-interrupted)
            [ "$status" -eq 125 ]
            [ ! -e "$state/result" ]
            [ ! -e "$state/supervision" ]
            cp "$effects" "$case_dir/effects-before-retry"
            invoke same-boot release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 125 ]
            grep -q 'Interrupted worker requires a new boot before release' "$case_dir/same-boot.stderr"
            mv "$worker-time" "$worker-time.real"
            changed_boot=$(sha256 -q -s legacy-test-next-boot)
            [ "$changed_boot" != "$(awk -F '\t' '$1=="boot" {print $2}' "$state/started")" ]
            cat > "$workspace/time-wrapper" <<EOF
#!/bin/sh
if [ "\$1" = boot ]; then printf '%s\\n' '$changed_boot'; exit 0; fi
exec '$worker-time.real' "\$@"
EOF
            install -m 0555 "$workspace/time-wrapper" "$worker-time"
            invoke released release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 0 ]
            grep -qx 'format.xcat-freebsd-postscript-release-1' "$state/released"
            [ ! -e "$base/active" ]
            invoke report evidence "$run"
            [ "$status" -eq 0 ]
            grep -qx 'format.xcat-freebsd-postscript-evidence-2' "$case_dir/report.stdout"
            mv -f "$worker-time.real" "$worker-time"
            invoke report-again evidence "$run"
            [ "$status" -eq 0 ]
            cmp "$case_dir/report.stdout" "$case_dir/report-again.stdout"
            cmp "$effects" "$case_dir/effects-before-retry"
            ;;
        package-failure|start-write-failure|interrupted|boot-observation-*|boot-release-*)
            [ "$status" -eq 125 ]
            [ ! -e "$state/result" ]
            if [ "$name" = package-failure ] || [ "$name" = start-write-failure ]; then
                [ ! -s "$effects" ]
            elif [ "$name" != interrupted ]; then
                ! grep -q '^second$' "$effects"
                ! grep -q '^after$' "$effects"
            fi
            cp "$effects" "$case_dir/effects-before-retry"
            invoke retry start "$run"
            lockf -k -t 10 "$base/lock" /bin/sh -c :
            cmp "$effects" "$case_dir/effects-before-retry"
            case "$name" in
            boot-observation-*|boot-release-*)
                mv "$worker-time" "$worker-time.real"
                cat > "$workspace/time-wrapper" <<EOF
#!/bin/sh
if [ "\$1" = boot ]; then
    case '$name' in *-failure) exit 1 ;; *) printf 'invalid-boot\\n'; exit 0 ;; esac
fi
exec '$worker-time.real' "\$@"
EOF
                install -m 0555 "$workspace/time-wrapper" "$worker-time"
                case "$name" in
                boot-observation-*) invoke faulty-boot receipt "$run" ;;
                *) invoke faulty-boot release-after-reboot "$run" "$snapshot" ;;
                esac
                mv -f "$worker-time.real" "$worker-time"
                [ "$status" -eq 125 ]
                grep -q 'boot' "$case_dir/faulty-boot.stderr"
                [ ! -s "$case_dir/faulty-boot.stdout" ]
                [ ! -e "$state/released" ]
                [ ! -e "$state/released.tmp" ]
                [ "$(cat "$base/active")" = "$run" ]
                cmp "$effects" "$case_dir/effects-before-retry"
                ;;
            esac
            invoke release release-after-reboot "$run" "$snapshot"
            [ "$status" -eq 125 ]
            ;;
        *)
            expected=0
            case "$name" in
            exit3|signal|exit143|timeout|log-timeout|sync-failure|sync-timeout|sync-late|package-options|package-missing-context|package-wrong-entry|package-unready) expected=1 ;;
            esac
            [ "$status" -eq "$expected" ]
            invoke receipt receipt "$run"; [ "$status" -eq 0 ]
            cp "$effects" "$case_dir/effects-before-retry"
            invoke retry run "$run"; [ "$status" -eq "$expected" ]
            cmp "$effects" "$case_dir/effects-before-retry"
            cmp "$case_dir/receipt.stdout" "$case_dir/retry.stdout"
            printf 'before\nfirst\nsecond\nafter\n' > "$case_dir/expected-effects"
            cmp "$effects" "$case_dir/expected-effects"
            case "$name" in
            delivery-*)
                [ ! -e "$upload" ] || rm "$upload"
                invoke delivered-again delivery "$run" "$snapshot" "$archive_digest" "$archive_bytes"
                [ "$status" -eq 0 ]
                [ "$(awk -F '\t' '$1=="state" {print $2}' "$case_dir/delivered-again.stdout")" = admitted ]
                [ "$(awk -F '\t' '$1=="path" {print $2}' "$case_dir/delivered-again.stdout")" = - ]
                invoke received-again receive "$run" "$snapshot" "$archive_digest" "$archive_bytes"
                [ "$status" -eq 0 ]
                cmp "$case_dir/delivered-again.stdout" "$case_dir/received-again.stdout"
                cmp "$effects" "$case_dir/effects-before-retry"
                ;;
            esac
            if [ "$name" = large-file ]; then [ "$(stat -f %z "$case_dir/payload")" -eq 2097152 ]; fi
            printf 'first\000two words\000\000' > "$case_dir/expected-argv"
            if [ "$name" = many-arguments ]; then
                printf 'first\000' > "$case_dir/expected-argv"
                argument=0
                while [ "$argument" -lt 255 ]; do
                    printf '%s\000' "$argument" >> "$case_dir/expected-argv"
                    argument=$((argument+1))
                done
            fi
            cmp "$state/entries/1/argv" "$case_dir/expected-argv"
            child_status=0
            case "$name" in exit3) child_status=3 ;; signal|exit143) child_status=143 ;; timeout|log-timeout) child_status=124 ;; esac
            case "$name" in
            package-options) child_status=1 ;;
            package-missing-context|package-wrong-entry|package-unready) child_status=125 ;;
            sync-failure) child_status=1 ;;
            sync-timeout|sync-late)
                child_status=$(awk -F '\t' '$1 == "status" {print $2}' "$state/entries/1/result")
                case "$child_status" in 124|125) ;; *) exit 1 ;; esac
                [ ! -e "$state/entries/1/sync.result" ]
                ;;
            esac
            [ "$(awk -F '\t' '$1 == "status" {print $2}' "$state/entries/1/result")" = "$child_status" ]
            case "$name" in
            descendant|descendant-inherited)
                child_pid=$(cat "$case_dir/owned.pid")
                "$worker-time" process "$child_pid" > "$case_dir/daemon.after"
                cmp "$case_dir/daemon.identity" "$case_dir/daemon.after"
                open=no
                [ "$name" != descendant-inherited ] || open=yes
                for stream in stdout stderr; do
                    [ "$(awk -F '\t' -v key="$stream-open" '$1 == key {print $2}' "$state/entries/1/result")" = "$open" ]
                done
                kill -TERM "$child_pid"
                ;;
            log-limit|stderr-limit|log-exact|stderr-exact|log-timeout)
                stream=stdout
                case "$name" in stderr-*) stream=stderr ;; esac
                truncated=yes
                case "$name" in *-exact) truncated=no ;; esac
                [ "$(stat -f %z "$state/entries/1/$stream")" = 4096 ]
                [ "$(awk -F '\t' -v key="$stream-truncated" '$1 == key {print $2}' "$state/entries/1/result")" = "$truncated" ]
                [ "$(awk -F '\t' '$1 == "log-limit" {print $2}' "$state/entries/1/result")" = 4096 ]
                [ ! -e "$base/active" ]
                invoke captured-evidence evidence "$run"
                [ "$status" -eq 0 ]
                ;;
            esac
            case "$name" in
            package-ospkgs|package-otherpkgs)
                [ "$(cat "$state/entries/1/stdout")" = 'recorder package status' ]
                invoke late-package-status package-status "$run" 1
                [ "$status" -eq 125 ]
                cmp "$effects" "$case_dir/effects-before-retry"
                ;;
            sync-duplicate)
                cp "$state/entries/1/sync.result" "$case_dir/sync-before"
                invoke duplicate sync-result "$run" "$snapshot" 1 0 "$evidence_digest"; [ "$status" -eq 0 ]
                invoke conflict sync-result "$run" "$snapshot" 1 1 "$evidence_digest"; [ "$status" -eq 125 ]
                cmp "$state/entries/1/sync.result" "$case_dir/sync-before"
                cmp "$effects" "$case_dir/effects-before-retry"
                ;;
            sync-late)
                invoke late sync-result "$run" "$snapshot" 1 0 "$evidence_digest"; [ "$status" -eq 125 ]
                [ ! -e "$state/entries/1/sync.result" ]
                ;;
            sync-success)
                invoke sync-evidence evidence "$run"; [ "$status" -eq 0 ]
                for member in request result; do
                    tar -xOf "$state/evidence/archive.tar" "entries/1/sync.$member" > "$case_dir/sync.$member"
                    cmp "$case_dir/sync.$member" "$state/entries/1/sync.$member"
                done
                ;;
            sync-skip-*) [ ! -e "$state/entries/1/sync.request" ] ;;
            esac
            for entry in 1 2; do
                started=$(awk -F '\t' '$1 == "started-epoch" {print $2}' "$state/entries/$entry/started")
                finished=$(awk -F '\t' '$1 == "finished-epoch" {print $2}' "$state/entries/$entry/result")
                [ "$started" -gt 0 ]
                [ "$finished" -ge "$started" ]
                [ "$finished" -le "$(date -u +%s)" ]
                start_uptime=$(awk -F '\t' '$1 == "started-uptime" {print $2}' "$state/entries/$entry/started")
                finish_uptime=$(awk -F '\t' '$1 == "finished-uptime" {print $2}' "$state/entries/$entry/result")
                [ "$start_uptime" -ge 0 ] && [ "$finish_uptime" -ge "$start_uptime" ]
                [ "$(awk -F '\t' '$1 == "started-sha256" {print $2}' "$state/entries/$entry/result")" = "$(sha256 -q "$state/entries/$entry/started")" ]
            done
            case "$name" in
            evidence*)
                if [ "$name" = evidence-publication ]; then
                    mkdir "$state/evidence"
                    invoke failed-evidence evidence "$run"
                    [ "$status" -eq 125 ]
                    rmdir "$state/evidence"
                fi
                invoke evidence evidence "$run"
                [ "$status" -eq 0 ]
                report=$state/evidence/archive.tar
                [ "$(awk -F '\t' '$1 == "path" {print $2}' "$case_dir/evidence.stdout")" = "$report" ]
                [ "$(awk -F '\t' '$1 == "archive-sha256" {print $2}' "$case_dir/evidence.stdout")" = "$(sha256 -q "$report")" ]
                [ "$(awk -F '\t' '$1 == "archive-bytes" {print $2}' "$case_dir/evidence.stdout")" = "$(stat -f %z "$report")" ]
                [ "$(awk -F '\t' '$1 == "receipt-sha256" {print $2}' "$case_dir/evidence.stdout")" = "$(sha256 -q "$state/result")" ]
                tar -tf "$report" > "$case_dir/evidence-members"
                [ "$(wc -l < "$case_dir/evidence-members" | tr -d ' ')" -eq 20 ]
                mkdir -m 0700 "$case_dir/evidence-readback"
                tar -xpf "$report" -C "$case_dir/evidence-readback"
                while IFS= read -r member; do cmp "$state/$member" "$case_dir/evidence-readback/$member"; done < "$case_dir/evidence-members"
                [ "$(cat "$case_dir/evidence-readback/entries/1/stdout")" = stdout ]
                [ "$(cat "$case_dir/evidence-readback/entries/1/stderr")" = stderr ]
                invoke evidence-retry evidence "$run"
                [ "$status" -eq 0 ]
                cmp "$case_dir/evidence.stdout" "$case_dir/evidence-retry.stdout"
                cmp "$effects" "$case_dir/effects-before-retry"
                case "$name" in
                evidence-archive-tamper) printf x | dd of="$report" bs=1 seek=512 conv=notrunc 2>/dev/null ;;
                evidence-start-tamper) sed 's/^started-epoch.*/started-epoch\t1/' "$state/entries/1/started" > "$case_dir/tampered"; cat "$case_dir/tampered" > "$state/entries/1/started" ;;
                evidence-finish-tamper) sed 's/^finished-epoch.*/finished-epoch\t1/' "$state/entries/1/result" > "$case_dir/tampered"; cat "$case_dir/tampered" > "$state/entries/1/result" ;;
                esac
                case "$name" in
                *-tamper)
                    invoke tampered-evidence evidence "$run"
                    [ "$status" -eq 125 ]
                    cmp "$effects" "$case_dir/effects-before-retry"
                    ;;
                esac
                ;;
            esac
            if [ "$name" = receipt-tamper ]; then
                printf 'corrupt\n' >> "$state/entries/1/stdout"
                invoke tampered receipt "$run"; [ "$status" -eq 125 ]
            elif [ "$name" = completed-active ]; then
                printf '%s\n' "$run" > "$base/active"
                invoke release-completed run "$run"; [ "$status" -eq 0 ]
                [ ! -e "$base/active" ]
                cmp "$effects" "$case_dir/effects-before-retry"
            elif [ "$name" = receipt-output-failure ]; then
                status=0
                (ulimit -f 0; "$worker" receipt "$run" > "$case_dir/failed-output" 2>/dev/null) || status=$?
                [ "$status" -ne 0 ]
                invoke recovered-receipt receipt "$run"; [ "$status" -eq 0 ]
                cmp "$case_dir/receipt.stdout" "$case_dir/recovered-receipt.stdout"
                cmp "$effects" "$case_dir/effects-before-retry"
            fi
            ;;
        esac
        ;;
    esac
    lockf -k -t 10 "$base/lock" /bin/sh -c :
    mv "$base" "$case_dir/state"
    printf 'PASS %s\n' "$name" | tee -a "$workspace/results"
done
[ "$case_number" -gt 0 ]
printf 'PASS cases=%s\n' "$case_number"

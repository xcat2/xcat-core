#!/bin/sh

# Run inside a disposable copy of a completed native postscript run.
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
[ "$(cat /input/retirement/disposable)" = xcat-freebsd-package-retirement-test-1 ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
base=/var/db/xcat/postscripts
worker=/usr/local/libexec/xcat-postscript
fixture=/input/retirement
run=$(cat "$fixture/run")
case "$run" in *[!0-9a-f]*) exit 2 ;; esac
[ "${#run}" -eq 32 ]
mkdir -m 0700 "$workspace"
finish()
{
    status=$?
    trap - EXIT
    for command in /sbin/fsync /bin/rm; do
        [ ! -e "$command.retention-real" ] || mv -f "$command.retention-real" "$command"
    done
    [ ! -e "$workspace/fsync-wrapper" ] || rm -f /sbin/fsync
    printf '%s\n' "$status" > "$workspace/exit-code"
    exit "$status"
}
trap finish EXIT

field()
{
    awk -F '\t' -v key="$2" '$1==key {print $2}' "$1"
}

invoke()
{
    label=$1
    shift
    status=0
    "$worker" "$@" > "$case_dir/$label.stdout" 2> "$case_dir/$label.stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/$label.status"
}

empty_payloads()
{
    [ "$(find "$state/bundle/archives" "$state/packages/archives" -type f | wc -l | tr -d ' ')" = 0 ]
    [ "$(stat -f '%u:%g:%l:%Lp' "$state/packages.retired")" = 0:0:1:600 ]
}

payload_snapshot()
{
    find "$state/bundle/archives" "$state/packages/archives" -type f -exec sha256 {} + | sort
}

metadata_bundle()
{
    new_run=ffffffffffffffffffffffffffffffff
    bundle=$base/incoming/$new_run
    cp -Rp "$state/bundle" "$bundle"
    chmod 0700 "$bundle/archives"
    : > "$case_dir/metadata.rows"
    while IFS= read -r row; do
        case "$row" in package*) ;; *) continue ;; esac
        id=$(printf '%s\n' "$row" | cut -f 2)
        tar -xOf "$bundle/archives/$id.pkg" +MANIFEST > "$bundle/archives/$id.manifest"
        if [ "$name:$id" = metadata-rejected:p0 ]; then
            sed 's/"comment":"/"comment":"changed /' "$bundle/archives/$id.manifest" > "$case_dir/changed.manifest"
            ! cmp -s "$bundle/archives/$id.manifest" "$case_dir/changed.manifest"
            cp "$case_dir/changed.manifest" "$bundle/archives/$id.manifest"
        fi
        chmod 0400 "$bundle/archives/$id.manifest"
        printf '%s\t%s\t%s\n' "$row" "$(stat -f %z "$bundle/archives/$id.manifest")" \
            "$(sha256 -q "$bundle/archives/$id.manifest")" >> "$case_dir/metadata.rows"
        rm "$bundle/archives/$id.pkg"
    done < "$state/bundle/request"
    printf 'format\txcat-freebsd-local-manifests-1\nplan\t%s\n' \
        "$(sha256 -q "$bundle/package.plan")" > "$bundle/request"
    cat "$case_dir/metadata.rows" >> "$bundle/request"
    case "$name" in
    metadata-size|metadata-digest)
        awk -F '\t' -v name="$name" 'BEGIN {OFS="\t"}
            NR==3 {if(name=="metadata-size") $13++; else $14=sprintf("%064d",0)} {print}' \
            "$bundle/request" > "$case_dir/changed.request"
        cp "$case_dir/changed.request" "$bundle/request"
        ;;
    metadata-missing) rm "$bundle/archives/p0.manifest" ;;
    metadata-extra) cp -p "$bundle/archives/p0.manifest" "$bundle/archives/extra" ;;
    metadata-link) rm "$bundle/archives/p0.manifest"; ln -s /input/retirement/run "$bundle/archives/p0.manifest" ;;
    esac
    chmod 0500 "$bundle/archives"
    if [ "$name" = metadata-execute ] || [ "$name" = metadata-script-failure ] ||
        [ "$name" = metadata-framework-failure ] || [ "$name" = metadata-rejected ]; then
        rm -rf "$bundle/tree"
        mkdir -m 0755 "$bundle/tree"
        script_status=0
        [ "$name" != metadata-script-failure ] || script_status=3
        printf '#!/bin/sh\nprintf "executed\\n" >> "%s"\nexit %s\n' "$case_dir/effects" "$script_status" \
            > "$bundle/tree/retention-proof"
        chmod 0555 "$bundle/tree/retention-proof"
        printf '1\tpostscripts\t%s\t%s\tretention-proof\n' "$(sha256 -q -s retention-proof)" \
            "$(sha256 -q "$bundle/tree/retention-proof")" > "$bundle/entries"
        cat > "$bundle/driver" <<'EOF'
#!/bin/sh
/usr/local/libexec/xcat-postscript begin "$1" 1 || exit 125
/usr/local/libexec/xcat-postscript execute "$1" 1 retention-proof || exit 125
EOF
        if [ "$name" = metadata-framework-failure ]; then
            printf 'exit 125\n' >> "$bundle/driver"
        else
            printf '/usr/local/libexec/xcat-postscript driver-complete "$1" 1 || exit 125\n' >> "$bundle/driver"
        fi
        mtree -c -K sha256digest -p "$bundle/tree" > "$bundle/tree.mtree"
    fi
    awk -F '\t' -v run="$new_run" -v request="$(sha256 -q "$bundle/request")" -v name="$name" '
        BEGIN {OFS="\t"}
        $1=="run" {$2=run} $1=="request" {$2=request}
        $1=="package-mode" {if(name!="metadata-update") $2="verify"}
        $1=="kind" {if(name=="metadata-repeat") $2="repeat"}
        $1=="format" {if(name=="metadata-repeat") $2="xcat-freebsd-postscript-bundle-3"}
        {print} END {if(name=="metadata-repeat") print "boot",sprintf("%064d",0)}' \
        "$state/bundle/manifest" | awk -F '\t' -v driver="$(sha256 -q "$bundle/driver")" \
            -v entries="$(sha256 -q "$bundle/entries")" -v tree="$(sha256 -q "$bundle/tree.mtree")" '
            BEGIN {OFS="\t"} $1=="driver" {$2=driver} $1=="entries" {$2=entries} $1=="tree" {$2=tree} {print}' \
            > "$bundle/manifest"
    invoke admit admit "$new_run" "$(sha256 -q "$bundle/manifest")"
    expected=125
    case "$name" in metadata-ok|metadata-execute|metadata-script-failure|metadata-framework-failure|metadata-rejected) expected=0 ;; esac
    [ "$status" -eq "$expected" ]
    [ ! -e "$base/runs/$new_run/started" ] && [ ! -e "$base/runs/$new_run/packages" ]
    if [ "$name" = metadata-execute ] || [ "$name" = metadata-script-failure ] ||
        [ "$name" = metadata-framework-failure ] || [ "$name" = metadata-rejected ]; then
        metadata_execute
    fi
}

metadata_execute()
{
    /usr/local/sbin/pkg-static -C /dev/null query -a '%n %v %a %k' > "$case_dir/database.before"
    invoke execute run "$new_run"
    expected=0 outcome=success
    case "$name" in metadata-script-failure|metadata-framework-failure|metadata-rejected) expected=1; outcome=failed ;; esac
    [ "$status" -eq "$expected" ]
    state=$base/runs/$new_run
    [ "$(field "$state/result" outcome)" = "$outcome" ]
    /usr/local/sbin/pkg-static -C /dev/null query -a '%n %v %a %k' > "$case_dir/database.after"
    cmp "$case_dir/database.before" "$case_dir/database.after"
    if [ "$name" = metadata-rejected ]; then
        [ "$(field "$state/result" format)" = xcat-freebsd-postscript-result-2 ]
        [ "$(field "$state/packages.rejected" phase)" = native ]
        [ ! -e "$case_dir/effects" ] && [ ! -e "$state/packages.retired" ]
        payload_snapshot > "$case_dir/rejected.before"; [ -s "$case_dir/rejected.before" ]
        invoke retire-rejected retire "$new_run"; [ "$status" -eq 125 ]
        invoke retry run "$new_run"; [ "$status" -eq 1 ]
        cmp "$state/result" "$case_dir/retry.stdout"
        payload_snapshot > "$case_dir/rejected.after"; cmp "$case_dir/rejected.before" "$case_dir/rejected.after"
        [ ! -e "$case_dir/effects" ] && [ ! -e "$state/packages.retired" ]
        return
    fi
    [ "$(field "$state/packages/local-verify.result" changes)" = 0 ]
    [ "$(field "$state/packages/local-verify.result" outcome)" = no-change ]
    [ "$(field "$state/packages/request" format)" = xcat-freebsd-local-manifests-1 ]
    [ "$(field "$state/packages/managed.request" format)" = xcat-freebsd-local-request-1 ]
    [ "$(cat "$case_dir/effects")" = executed ]
    empty_payloads
    invoke receipt receipt "$new_run"; [ "$status" -eq 0 ]; cmp "$state/result" "$case_dir/receipt.stdout"
    invoke retry run "$new_run"; [ "$status" -eq "$expected" ]
    [ "$(cat "$case_dir/effects")" = executed ]
    if [ "$name" = metadata-framework-failure ]; then
        [ "$(field "$state/result" format)" = xcat-freebsd-postscript-result-3 ]
        [ ! -e "$state/driver.complete" ] && [ ! -e "$base/active" ]
        cmp "$state/result" "$state/failure/content/result"
        invoke evidence evidence "$new_run"; [ "$status" -eq 0 ]
        [ "$(field "$case_dir/evidence.stdout" format)" = xcat-freebsd-postscript-evidence-4 ]
        invoke retire-failure retire "$new_run"; [ "$status" -eq 0 ]
        cmp "$state/result" "$case_dir/retire-failure.stdout"
        empty_payloads
        [ "$(cat "$case_dir/effects")" = executed ]
    fi
}

cases='complete explicit active uncertain uncommitted rejected invalid-result missing-payload extra-payload symlink-payload staged-interrupt marker-interrupt partial-delete payload-sync bad-marker new-head metadata-ok metadata-size metadata-digest metadata-missing metadata-extra metadata-link metadata-update metadata-repeat metadata-execute metadata-script-failure metadata-framework-failure metadata-rejected'
count=0
for name in $cases; do
    if [ -n "${XCAT_FREEBSD_RETENTION_CASES-}" ]; then
        case " $XCAT_FREEBSD_RETENTION_CASES " in *" $name "*) ;; *) continue ;; esac
    fi
    case_dir=$workspace/$name
    mkdir -m 0700 "$case_dir"
    [ ! -e "$base" ] && [ ! -L "$base" ]
    mkdir -m 0700 "$base" "$base/incoming" "$base/runs"
    run=$(cat "$fixture/run")
    input_state=$fixture/state
    if [ "$name" = rejected ]; then
        run=00000000000000000000000000000001
        input_state=$fixture/rejected
    fi
    cp -Rp "$input_state" "$base/runs/$run"
    state=$base/runs/$run
    if [ "$name" = rejected ]; then
        cp -p "$fixture/advanced-head" "$base/package-head"
    else
        cp -p "$state/package-head" "$base/package-head"
    fi
    snapshot=$(cat "$state/snapshot")
    payload_snapshot > "$case_dir/payloads.before"
    [ "$name" = rejected ] || [ -s "$case_dir/payloads.before" ]
    case "$name" in
    metadata-*) metadata_bundle ;;
    *)
        expected=125
        case "$name" in
        complete|explicit|new-head) expected=0 ;;
        active) printf '%s\n' "$run" > "$base/active" ;;
        uncertain) mv "$state/result" "$case_dir/saved.result" ;;
        uncommitted) mv "$state/package-head" "$case_dir/saved.head" ;;
        invalid-result) printf 'changed\n' >> "$state/result" ;;
        missing-payload) rm "$state/bundle/archives/p0.pkg" ;;
        extra-payload) cp -p "$state/bundle/archives/p0.pkg" "$state/bundle/archives/extra" ;;
        symlink-payload) rm "$state/bundle/archives/p0.pkg"; ln -s /input/retirement/run "$state/bundle/archives/p0.pkg" ;;
        staged-interrupt|marker-interrupt|payload-sync)
            [ ! -e /sbin/fsync ]
            : > "$workspace/fsync-wrapper"
            stop=$state/packages.retired
            [ "$name" != staged-interrupt ] || stop=$state/packages.retired.next
            [ "$name" != payload-sync ] || stop=$state/bundle/archives
            printf '#!/bin/sh\n[ "$1" != "%s" ] || exit 1\nexec /usr/bin/fsync "$@"\n' "$stop" > /sbin/fsync
            chmod 0555 /sbin/fsync
            ;;
        partial-delete)
            mv /bin/rm /bin/rm.retention-real
            printf '#!/bin/sh\n[ "$1" != "%s" ] || exit 1\nexec /bin/rm.retention-real "$@"\n' \
                "$state/bundle/archives/p1.pkg" > /bin/rm
            chmod 0555 /bin/rm
            ;;
        bad-marker)
            invoke first retire "$run"
            [ "$status" -eq 0 ]
            printf 'changed\n' >> "$state/packages.retired"
            ;;
        esac
        if [ "$name" = new-head ]; then cp -p "$fixture/advanced-head" "$base/package-head"; fi
        operation=retire
        [ "$name" != complete ] || operation=run
        invoke retire "$operation" "$run"
        [ "$status" -eq "$expected" ]
        case "$name" in
        complete|explicit|new-head)
            empty_payloads
            cmp "$fixture/state/result" "$case_dir/retire.stdout"
            for operation in receipt start; do
                invoke "$operation" "$operation" "$run"
                [ "$status" -eq 0 ]; cmp "$fixture/state/result" "$case_dir/$operation.stdout"
            done
            invoke readmit admit "$run" "$snapshot"; [ "$status" -eq 0 ]
            invoke evidence evidence "$run"; [ "$status" -eq 0 ]
            invoke retry retire "$run"; [ "$status" -eq 0 ]; empty_payloads
            [ "$name" != new-head ] || cmp "$base/package-head" "$fixture/advanced-head"
            ;;
        staged-interrupt|marker-interrupt|partial-delete|payload-sync)
            if [ "$name" = staged-interrupt ]; then
                [ ! -e "$state/packages.retired" ] && [ -f "$state/packages.retired.next" ]
            else
                [ -f "$state/packages.retired" ]
            fi
            if [ "$name" = partial-delete ]; then
                [ ! -e "$state/bundle/archives/p0.pkg" ] && [ -f "$state/bundle/archives/p1.pkg" ]
                mv -f /bin/rm.retention-real /bin/rm
            else
                rm /sbin/fsync "$workspace/fsync-wrapper"
                if [ "$name" = marker-interrupt ] || [ "$name" = staged-interrupt ]; then
                    payload_snapshot > "$case_dir/payloads.interrupted"
                    cmp "$case_dir/payloads.before" "$case_dir/payloads.interrupted"
                fi
            fi
            invoke receipt receipt "$run"; [ "$status" -eq 0 ]
            cmp "$fixture/state/result" "$case_dir/receipt.stdout"
            invoke retry retire "$run"; [ "$status" -eq 0 ]; empty_payloads
            ;;
        bad-marker)
            invoke readmit admit "$run" "$snapshot"; [ "$status" -eq 125 ]
            ;;
        rejected)
            [ ! -e "$state/packages.retired" ]
            invoke retry run "$run"; [ "$status" -eq 1 ]
            cmp "$input_state/result" "$case_dir/retry.stdout"
            payload_snapshot > "$case_dir/payloads.after"; cmp "$case_dir/payloads.before" "$case_dir/payloads.after"
            ;;
        *)
            [ ! -e "$state/packages.retired" ]
            case "$name" in
            missing-payload|extra-payload|symlink-payload) ;;
            *) payload_snapshot > "$case_dir/payloads.after"; cmp "$case_dir/payloads.before" "$case_dir/payloads.after" ;;
            esac
            ;;
        esac
        ;;
    esac
    cmp "$fixture/initial-result" /var/db/xcat/pkgbase-install/result
    mv "$base" "$case_dir/state"
    count=$((count+1))
    printf 'PASS %s\n' "$name" | tee -a "$workspace/results"
done
[ "$count" -gt 0 ]
printf 'RETIREMENT_CASES_COMPLETE %s\n' "$count"

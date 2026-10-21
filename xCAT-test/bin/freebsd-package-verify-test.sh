#!/bin/sh

# Native acceptance for the installed verifier. The fixture directory contains
# the update fixture archives and a TSV catalogue: key, name, version, origin,
# ABI, archive bytes and SHA256. Run only on a disposable FreeBSD test node.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 022
[ "$#" -eq 4 ] || [ "$#" -eq 5 ]
workspace=$1
helper=$2
control=$3
fixtures=$4
baseline=${5:-$helper}
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
for path in "$workspace" "$helper" "$control" "$fixtures" "$baseline"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
done
[ ! -e "$workspace" ]
[ ! -L "$workspace" ]
[ -x "$helper" ]
[ -x "$control" ]
[ -x "$baseline" ]
[ -f "$fixtures/catalogue" ]
mkdir -m 0700 "$workspace" "$workspace/roots"
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

config()
{
    cat <<'EOF'
ABI = "FreeBSD:15:amd64";
OSVERSION = 1501000;
PKG_DBDIR = "/var/db/pkg";
PKG_CACHEDIR = "/work/operation/cache";
REPOS_DIR = [];
REPOSITORIES = {};
REPO_AUTOUPDATE = false;
PKG_ENABLE_PLUGINS = false;
PKG_TRIGGERS_ENABLE = true;
RUN_SCRIPTS = true;
HANDLE_RC_SCRIPTS = false;
SYSLOG = false;
IGNORE_OSVERSION = false;
PERMISSIVE = false;
CASE_SENSITIVE_MATCH = true;
PKG_ENV = {};
EOF
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

mount_devices()
{
    active=$1/dev
    mount -t devfs devfs "$active"
    devfs -m "$active" rule apply hide
    for device in null zero random urandom; do devfs -m "$active" rule apply path "$device" unhide; done
}

inside()
{
    env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C chroot "$root" "$@"
}

base=$workspace/base
mkdir -m 0755 "$base"
for directory in bin etc dev lib libexec usr/bin usr/lib usr/local/share/pkg var/db/pkg tmp tools; do mkdir -p "$base/$directory"; done
mkdir -m 0700 "$base/work" "$base/work/cache" "$base/work/repos" "$base/probe" "$base/fixtures"
cp -p "$helper" "$base/tools/helper"
cp -p "$control" "$base/tools/control"
cp -p "$baseline" "$base/tools/baseline"
cp -p /usr/local/sbin/pkg-static "$base/tools/pkg"
for path in /bin/sh /bin/cat /bin/mkdir /bin/rm /usr/bin/id /usr/bin/stat; do cp -p "$path" "$base$path"; done
cp -p /etc/passwd /etc/group /etc/pwd.db "$base/etc/"
printf '/libexec/ld-elf.so.1\n' > "$workspace/libraries.raw"
for path in "$base/tools/helper" "$base/bin/sh" "$base/bin/cat" "$base/bin/mkdir" "$base/bin/rm" "$base/usr/bin/id" "$base/usr/bin/stat"; do
    ldd "$path" >> "$workspace/loader"
done
! grep -q 'not found' "$workspace/loader"
awk '$2=="=>" && $3 ~ /^\// {print $3}' "$workspace/loader" >> "$workspace/libraries.raw"
sort -u "$workspace/libraries.raw" > "$workspace/libraries"
while IFS= read -r path; do
    mkdir -p "$base$(dirname "$path")"
    cp -p "$path" "$base$path"
    sha256 "$path"
done < "$workspace/libraries" > "$workspace/libraries.sha256"
cp -p "$fixtures/archives/"*.pkg "$base/fixtures/"
printf '%s\n' 'ABI="FreeBSD:15:amd64"; OSVERSION=1501000; PKG_DBDIR="/var/db/pkg"; PKG_CACHEDIR="/work/cache"; REPOS_DIR=[]; REPOSITORIES={}; REPO_AUTOUPDATE=false; PKG_ENABLE_PLUGINS=false; PKG_TRIGGERS_ENABLE=false; RUN_SCRIPTS=true; HANDLE_RC_SCRIPTS=false; SYSLOG=false;' > "$base/work/setup.conf"
root=$base
mount_devices "$root"
for name in anchor outside lib1 app1; do inside /tools/pkg -C /work/setup.conf -R /work/repos add -q "/fixtures/$name.pkg"; done
inside /tools/pkg -C /work/setup.conf -R /work/repos set -y -A 1 xcat-update-outside
inside /tools/pkg -C /work/setup.conf -R /work/repos lock -y xcat-update-outside
umount "$active"; active=
base_hash=$(sha256 -q "$base/var/db/pkg/local.sqlite")

cases='satisfied subset addition upgrade repacked missing-archive bad-archive missing-prior wrong-prior pending-trigger replay-marker explicit-update guard-control
empty-verify empty-update empty-missing-prior empty-prior empty-wrong-prior empty-uninstalled-prior empty-extra-archive empty-pending-trigger empty-bad-header empty-check empty-install empty-finalize
update-rejected update-script-failure update-script-exit3 update-script-interrupted'
[ "$#" -ne 5 ] || cases="$cases empty-control"
if [ -n "${XCAT_FREEBSD_VERIFY_CASES-}" ]; then
    for selected in $XCAT_FREEBSD_VERIFY_CASES; do
        found=no
        for name in $cases; do [ "$selected" != "$name" ] || found=yes; done
        [ "$found" = yes ] || exit 2
    done
    cases=$XCAT_FREEBSD_VERIFY_CASES
fi
count=0
for name in $cases; do
    root=$workspace/roots/$name
    mkdir -m 0755 "$root"
    cp -a "$base/." "$root/"
    operation=$root/work/operation
    mkdir -m 0700 "$operation" "$operation/cache" "$operation/repos" "$operation/archives"
    case "$name" in
    empty-*) keys= ;;
    subset) keys=anchor ;;
    upgrade) keys='lib2 app2' ;;
    repacked|update-rejected) keys=repack ;;
    update-script-failure) keys=exit2 ;;
    update-script-exit3) keys=exit3 ;;
    update-script-interrupted) keys=interrupt ;;
    addition|explicit-update|guard-control) keys='anchor lib2 app2 extra' ;;
    *) keys='anchor lib1 app1' ;;
    esac
    request "$operation/request" $keys
    request "$operation/prior-request" anchor lib1 app1
    config > "$operation/config"
    chmod 0400 "$operation/config"
    index=0
    for key in $keys; do
        cp -p "$fixtures/archives/$key.pkg" "$operation/archives/p$index.pkg"
        chmod 0400 "$operation/archives/p$index.pkg"
        index=$((index+1))
    done
    case "$name" in
    empty-missing-prior) rm "$operation/prior-request" ;;
    empty-prior) request "$operation/prior-request" ;;
    empty-wrong-prior) request "$operation/prior-request" anchor lib2 app2 ;;
    empty-uninstalled-prior) request "$operation/prior-request" anchor lib1 extra ;;
    empty-extra-archive) cp -p "$fixtures/archives/anchor.pkg" "$operation/archives/p0.pkg"; chmod 0400 "$operation/archives/p0.pkg" ;;
    empty-pending-trigger) mkdir -m 0755 "$root/var/db/pkg/triggers"; printf 'return 0\n' > "$root/var/db/pkg/triggers/Pending1" ;;
    empty-bad-header) printf 'format\txcat-freebsd-local-request-1\n' > "$operation/request" ;;
    missing-archive) rm "$operation/archives/p0.pkg" ;;
    bad-archive) printf corrupt >> "$operation/archives/p0.pkg" ;;
    missing-prior) rm "$operation/prior-request" ;;
    wrong-prior) request "$operation/prior-request" anchor lib2 app2 ;;
    pending-trigger) mkdir -m 0755 "$root/var/db/pkg/triggers"; printf 'return 0\n' > "$root/var/db/pkg/triggers/Pending1" ;;
    replay-marker) : > "$operation/local-verify.started" ;;
    esac
    chmod 0500 "$operation/archives"
    target=/
    operation_config=/work/operation/config
    case "$name" in
    empty-check)
        mkdir -m 0700 "$operation/root" "$operation/db"
        target=/work/operation/root
        ;;
    empty-install|empty-finalize)
        mkdir -p "$root/target/var/db/pkg" "$root/target/var/cache/pkg" "$root/target/var/db/xcat/pkg-apply"
        chmod 0700 "$root/target/var/db/xcat/pkg-apply"
        mkdir -m 0700 "$root/target/var/db/xcat/pkg-apply/repos"
        target=/target
        if [ "$name" = empty-finalize ]; then
            cp -p "$operation/config" "$root/target/var/db/xcat/pkg-apply/config"
            operation_config=/target/var/db/xcat/pkg-apply/config
        fi
        ;;
    esac
    mount_devices "$root"
    inside /tools/pkg -C /dev/null query -a '%n %v' > "$root/work/before"
    cp "$root/probe/actions" "$root/work/actions-before"
    command=local-verify
    executable=/tools/helper
    case "$name" in
    explicit-update|empty-update|update-*) command=local-update ;;
    empty-check) command=local-check ;;
    empty-install) command=local-install ;;
    empty-finalize) command=local-finalize ;;
    empty-control) executable=/tools/baseline ;;
    esac
    [ "$name" != guard-control ] || executable=/tools/control
    status=0
    inside "$executable" -C "$operation_config" "$command" /work/operation/request "$target" \
        > "$root/work/stdout" 2> "$root/work/stderr" || status=$?
    printf '%s\n' "$status" > "$root/work/status"
    inside /tools/pkg -C /dev/null query -a '%n %v' > "$root/work/after"
    case "$name" in
    satisfied|subset|empty-verify|empty-update)
        [ "$status" -eq 0 ]
        cmp "$root/work/before" "$root/work/after"
        cmp "$root/probe/actions" "$root/work/actions-before"
        grep -q '^changes[[:space:]]0$' "$operation/$command.result"
        grep -q '^actions[[:space:]]0$' "$operation/$command.result"
        grep -q '^complete[[:space:]]yes$' "$operation/$command.result"
        case "$name" in empty-*) [ "$(wc -l < "$operation/request" | tr -d ' ')" -eq 2 ] ;; esac
        [ "$(grep -c '^package' "$operation/managed.request")" -eq 3 ]
        ;;
    explicit-update|guard-control)
        [ "$status" -eq 0 ]
        [ "$(grep -c '^xcat-update-' "$root/work/after")" -eq 5 ]
        grep -q '^xcat-update-app 2$' "$root/work/after"
        grep -q '^xcat-update-lib 2$' "$root/work/after"
        grep -q '^xcat-update-extra 1$' "$root/work/after"
        grep -q '^changes[[:space:]]3$' "$operation/$command.result"
        printf 'app 1\napp 2\n' > "$root/work/expected-actions"
        cmp "$root/probe/actions" "$root/work/expected-actions"
        ;;
    update-script-failure|update-script-exit3|update-script-interrupted)
        if [ "$name" = update-script-exit3 ]; then
            [ "$status" -eq 0 ]
        else
            [ "$status" -ne 0 ]
        fi
        [ ! -e "$operation/$command.result" ]
        grep -q "^$keys entry$" "$root/probe/actions"
        ;;
    *)
        [ "$status" -ne 0 ]
        [ ! -e "$operation/$command.result" ]
        cmp "$root/work/before" "$root/work/after"
        cmp "$root/probe/actions" "$root/work/actions-before"
        ;;
    esac
    if [ "$status" -eq 0 ] && [ "$name" != update-script-exit3 ]; then
        installed=$(wc -l < "$root/work/after" | tr -d ' ')
        [ "$(awk -F '\t' '$1=="packages" {print $2}' "$operation/$command.result")" = "$installed" ]
    fi
    case "$name" in
    addition|upgrade|repacked|wrong-prior|pending-trigger|empty-wrong-prior|empty-uninstalled-prior|empty-pending-trigger|update-rejected)
        rejection=$operation/$command.rejected
        [ -f "$rejection" ]
        [ ! -L "$rejection" ]
        [ "$(stat -f '%u:%g:%l:%Lp' "$rejection")" = 0:0:1:600 ]
        printf 'format\txcat-freebsd-local-rejection-1\nscope\t%s\nplan-reference\t%s\nrequest-sha256\t%s\nprior-request-sha256\t%s\nconfig-sha256\t%s\npkg\t2.6.2\napply\tnot-started\noutcome\trejected\ncomplete\tyes\n' \
            "$command" "$(awk -F '\t' '$1=="plan" {print $2}' "$operation/request")" \
            "$(sha256 -q "$operation/request")" "$(sha256 -q "$operation/prior-request")" \
            "$(sha256 -q "$operation/config")" > "$root/work/rejection.expected"
        cmp "$root/work/rejection.expected" "$rejection"
        replay_status=0
        inside /tools/helper -C /work/operation/config "$command" /work/operation/request / \
            > "$root/work/rejection-replay.stdout" 2> "$root/work/rejection-replay.stderr" || replay_status=$?
        [ "$replay_status" -ne 0 ]
        grep -q 'local apply phase has already started or has a result' "$root/work/rejection-replay.stderr"
        cmp "$root/work/rejection.expected" "$rejection"
        cmp "$root/probe/actions" "$root/work/actions-before"
        ;;
    *)
        [ ! -e "$operation/local-update.rejected" ]
        [ ! -e "$operation/local-verify.rejected" ]
        ;;
    esac
    case "$name" in
    empty-wrong-prior|empty-uninstalled-prior)
        grep -q 'empty operation prior provenance differs from installed state' "$root/work/stderr" ;;
    empty-control|empty-check|empty-install|empty-finalize|empty-prior|empty-bad-header)
        grep -q 'local-check requires package records' "$root/work/stderr" ;;
    esac
    inside /tools/pkg -C /dev/null query '%a %k' xcat-update-outside > "$root/work/outside-flags"
    [ "$(cat "$root/work/outside-flags")" = '1 1' ]
    if [ "$name" = satisfied ] || [ "$name" = explicit-update ] || [ "$name" = empty-verify ] || [ "$name" = empty-update ]; then
        cp "$operation/$command.result" "$root/work/result-before"
        status=0
        inside /tools/helper -C /work/operation/config "$command" /work/operation/request / \
            > "$root/work/replay.stdout" 2> "$root/work/replay.stderr" || status=$?
        [ "$status" -ne 0 ]
        cmp "$operation/$command.result" "$root/work/result-before"
    fi
    umount "$active"; active=
    printf 'PASS %s\n' "$name" | tee -a "$workspace/results"
    count=$((count+1))
done
[ "$(sha256 -q "$base/var/db/pkg/local.sqlite")" = "$base_hash" ]
printf 'PASS cases=%s\n' "$count"

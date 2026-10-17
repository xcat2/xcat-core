#!/bin/sh

# Exercise native ABI compatibility and dependency comparison with real packages.
# Run only on a disposable FreeBSD node. Keep the workspace for evidence.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 022
[ "$#" -eq 2 ]
workspace=$1
helper=$2
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
for path in "$workspace" "$helper"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!A-Za-z0-9_./+-]*) exit 2 ;; esac
done
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
[ -x "$helper" ]
mkdir -m 0700 "$workspace" "$workspace/fixtures" "$workspace/cases"
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

profile()
{
    cat <<EOF
ABI = "FreeBSD:15:amd64";
OSVERSION = 1501000;
PKG_DBDIR = "$1";
PKG_CACHEDIR = "$2";
REPOS_DIR = [];
REPOSITORIES = {};
REPO_AUTOUPDATE = false;
PKG_ENABLE_PLUGINS = false;
PKG_TRIGGERS_ENABLE = $3;
RUN_SCRIPTS = $3;
HANDLE_RC_SCRIPTS = false;
SYSLOG = false;
IGNORE_OSVERSION = false;
PERMISSIVE = false;
CASE_SENSITIVE_MATCH = true;
PKG_ENV = {};
EOF
}

mount_devices()
{
    active=$1/dev
    mount -t devfs devfs "$active"
    devfs -m "$active" rule apply hide
    for device in null zero random urandom; do
        devfs -m "$active" rule apply path "$device" unhide
    done
}

clean()
{
    env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C "$@"
}

inside()
{
    clean chroot "$root" "$@"
}

make_package()
{
    component=$1
    version=$2
    package_abi=$3
    dependencies=$4
    payload=$fixtures/payload-$component-$version
    mkdir -p "$payload/usr/local/share/xcat-abi"
    file=/usr/local/share/xcat-abi/$component.txt
    printf '%s %s\n' "$component" "$version" > "$payload$file"
    digest=$(sha256 -q "$payload$file")
    bytes=$(stat -f '%z' "$payload$file")
    manifest=$fixtures/$component-$version.json
    cat > "$manifest" <<EOF
{"name":"xcat-abi-$component","version":"$version","origin":"misc/xcat-abi-$component",
"comment":"Native ABI fixture","desc":"Native ABI fixture",
"maintainer":"root@example.invalid","www":"https://example.invalid",
"prefix":"/usr/local","abi":"$package_abi","flatsize":$bytes,
"licenselogic":"single","licenses":["BSD2CLAUSE"],
"files":{"$file":"$digest"},"deps":$dependencies}
EOF
    clean /usr/local/sbin/pkg-static -C "$workspace/create.conf" create \
        -M "$manifest" -r "$payload" -o "$fixtures/archives" \
        > "$fixtures/$component-$version.create.stdout" \
        2> "$fixtures/$component-$version.create.stderr"
    archive=$fixtures/archives/xcat-abi-$component-$version.pkg
    tar -xOf "$archive" +MANIFEST > "$fixtures/$component-$version.manifest"
    sha256 "$archive" >> "$fixtures/archives.sha256"
}

stage()
{
    destination=$1
    revision=$2
    request_abi=$3
    mkdir -m 0700 "$destination" "$destination/archives" "$destination/repos" "$destination/cache"
    : > "$destination/rows"
    ordinal=0
    for component in app zdep adep mdep; do
        version=1
        abi=FreeBSD:15:amd64
        case "$component" in app|zdep) version=$revision ;; esac
        [ "$component" != app ] || abi=$request_abi
        filename=xcat-abi-$component-$version.pkg
        archive=$fixtures/archives/$filename
        digest=$(sha256 -q "$archive")
        bytes=$(stat -f '%z' "$archive")
        printf 'package\tp%s\tr1\txcat-abi-%s\t%s\tmisc/xcat-abi-%s\t%s\tAll/%s\tapplications/All/%s\t%s\t%s\t%s\n' \
            "$ordinal" "$component" "$version" "$component" "$abi" "$filename" "$filename" \
            "$bytes" "$digest" "$digest" >> "$destination/rows"
        cp -p "$archive" "$destination/archives/p$ordinal.pkg"
        chmod 0400 "$destination/archives/p$ordinal.pkg"
        ordinal=$((ordinal+1))
    done
    printf 'format\txcat-freebsd-local-request-1\nplan\t%s\n' "$(sha256 -q "$destination/rows")" > "$destination/request"
    cat "$destination/rows" >> "$destination/request"
    chmod 0400 "$destination/request"
    chmod 0500 "$destination/archives"
}

run()
{
    label=$1
    expected=$2
    shift 2
    status=0
    "$@" > "$case_root/$label.stdout" 2> "$case_root/$label.stderr" || status=$?
    printf '%s\n' "$status" > "$case_root/$label.status"
    [ "$status" -eq "$expected" ]
}

receipt()
{
    [ "$(stat -f '%u:%g:%l:%Lp' "$1")" = 0:0:1:600 ]
    grep -q '^complete[[:space:]]yes$' "$1"
}

live_stage()
{
    operation=$root/work/$1
    stage "$operation" "$2" "$3"
    cp -p "$4" "$operation/prior-request"
    chmod 0400 "$operation/prior-request"
    profile /var/db/pkg "/work/$1/cache" true > "$operation/config"
    chmod 0400 "$operation/config"
}

base=$workspace/base
mkdir -m 0755 "$base"
for directory in bin etc dev lib libexec usr/lib var/db/pkg var/cache/pkg tools; do
    mkdir -p "$base/$directory"
done
mkdir -m 0700 "$base/work" "$workspace/create-db" "$workspace/create-cache"
cp -p "$helper" "$base/tools/helper"
cp -p /usr/local/sbin/pkg-static "$base/tools/pkg"
cp -p /bin/sh "$base/bin/sh"
cp -p /etc/passwd /etc/group /etc/pwd.db "$base/etc/"
printf '/libexec/ld-elf.so.1\n' > "$workspace/libraries.raw"
for path in "$base/tools/helper" "$base/bin/sh"; do
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
profile "$workspace/create-db" "$workspace/create-cache" false > "$workspace/create.conf"
[ "$(clean /usr/local/sbin/pkg-static -C "$workspace/create.conf" -v)" = 2.6.2 ]
[ "$(clean "$helper" -C "$workspace/create.conf" -v)" = 2.6.2 ]

cases='exact wildcard any-version version-only os-only lowercase wrong-release wrong-architecture global-wildcard request-mismatch'
if [ -n "${XCAT_FREEBSD_ABI_CASES-}" ]; then
    for selected in $XCAT_FREEBSD_ABI_CASES; do
        found=no
        for name in $cases; do [ "$selected" != "$name" ] || found=yes; done
        [ "$found" = yes ] || exit 2
    done
    cases=$XCAT_FREEBSD_ABI_CASES
fi
count=0
for name in $cases; do
    case "$name" in
    exact) selected_abi=FreeBSD:15:amd64 ;;
    wildcard|request-mismatch) selected_abi='FreeBSD:15:*' ;;
    any-version) selected_abi='FreeBSD:*' ;;
    version-only) selected_abi=FreeBSD:15 ;;
    os-only) selected_abi=FreeBSD ;;
    lowercase) selected_abi=freebsd:15:amd64 ;;
    wrong-release) selected_abi='FreeBSD:16:*' ;;
    wrong-architecture) selected_abi=FreeBSD:15:aarch64 ;;
    global-wildcard) selected_abi='*' ;;
    esac
    fixtures=$workspace/fixtures/$name
    mkdir -m 0700 "$fixtures" "$fixtures/archives"
    for component in adep mdep zdep; do make_package "$component" 1 FreeBSD:15:amd64 '{}'; done
    make_package zdep 2 FreeBSD:15:amd64 '{}'
    for revision in 1 2; do
        # Deliberately supply nonalphabetic dependency order to the native producer.
        dependencies='{"xcat-abi-zdep":{"origin":"misc/xcat-abi-zdep","version":"'"$revision"'"},"xcat-abi-adep":{"origin":"misc/xcat-abi-adep","version":"1"},"xcat-abi-mdep":{"origin":"misc/xcat-abi-mdep","version":"1"}}'
        make_package app "$revision" "$selected_abi" "$dependencies"
    done
    case_root=$workspace/cases/$name
    mkdir -m 0700 "$case_root"
    check=$case_root/check
    request_abi=$selected_abi
    [ "$name" != request-mismatch ] || request_abi=FreeBSD:15:amd64
    stage "$check" 1 "$request_abi"
    mkdir -m 0700 "$check/db" "$check/root"
    profile "$check/db" "$check/cache" false > "$check/config"
    chmod 0400 "$check/config"
    case "$name" in
    wrong-*|global-wildcard|request-mismatch)
        run check 1 clean "$helper" -C "$check/config" local-check "$check/request" "$check/root"
        [ ! -e "$check/local-check.result" ]
        [ -z "$(find "$check/root" -mindepth 1 -print)" ]
        if [ "$name" != request-mismatch ]; then
            grep -q 'requires a supported target ABI' "$case_root/check.stderr"
        fi
        count=$((count+1))
        printf 'ABI_CASE %s PASS\n' "$name"
        continue ;;
    esac
    run check 0 clean "$helper" -C "$check/config" local-check "$check/request" "$check/root"
    receipt "$check/local-check.result"
    [ -z "$(find "$check/root" -mindepth 1 -print)" ]
    root=$case_root/target
    mkdir -m 0755 "$root"
    (tar -C "$base" -cpf - .; printf '%s\n' "$?" > "$case_root/copy.status") | tar -C "$root" -xpf -
    [ "$(cat "$case_root/copy.status")" -eq 0 ]
    install=$case_root/install
    stage "$install" 1 "$selected_abi"
    profile "$root/var/db/pkg" "$root/var/cache/pkg" true > "$install/config"
    chmod 0400 "$install/config"
    mkdir -p "$root/var/db/xcat"
    mkdir -m 0700 "$root/var/db/xcat/pkg-apply" "$root/var/db/xcat/pkg-apply/repos"
    profile /var/db/pkg /var/cache/pkg true > "$root/var/db/xcat/pkg-apply/config"
    chmod 0400 "$root/var/db/xcat/pkg-apply/config"
    mount_devices "$root"
    run install 0 clean "$helper" -C "$install/config" local-install "$install/request" "$root"
    receipt "$install/local-install.result"
    run finalize 0 clean "$helper" -C "$root/var/db/xcat/pkg-apply/config" local-finalize "$install/request" "$root"
    receipt "$install/local-finalize.result"
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_root/installed.before"
    [ "$(wc -l < "$case_root/installed.before" | tr -d ' ')" -eq 4 ]
    inside /tools/pkg -C /dev/null query '%dn %dv' xcat-abi-app > "$case_root/database-dependencies"
    clean /usr/local/sbin/pkg-static -C "$workspace/create.conf" query -F "$fixtures/archives/xcat-abi-app-1.pkg" '%dn %dv' > "$case_root/archive-dependencies"
    printf 'xcat-abi-zdep 1\nxcat-abi-mdep 1\nxcat-abi-adep 1\n' > "$case_root/expected-database-dependencies"
    printf 'xcat-abi-adep 1\nxcat-abi-mdep 1\nxcat-abi-zdep 1\n' > "$case_root/expected-archive-dependencies"
    cmp "$case_root/database-dependencies" "$case_root/expected-database-dependencies"
    cmp "$case_root/archive-dependencies" "$case_root/expected-archive-dependencies"
    [ "$(cat "$root/usr/local/share/xcat-abi/app.txt")" = 'app 1' ]
    live_stage verify 1 "$selected_abi" "$install/request"
    run verify 0 inside /tools/helper -C /work/verify/config local-verify /work/verify/request /
    receipt "$operation/local-verify.result"
    grep -q '^changes[[:space:]]0$' "$operation/local-verify.result"
    grep -q '^actions[[:space:]]0$' "$operation/local-verify.result"
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_root/installed.verified"
    cmp "$case_root/installed.before" "$case_root/installed.verified"
    prior=$operation/managed.request
    live_stage update 2 "$selected_abi" "$prior"
    run update 0 inside /tools/helper -C /work/update/config local-update /work/update/request /
    receipt "$operation/local-update.result"
    grep -q '^changes[[:space:]]2$' "$operation/local-update.result"
    [ "$(cat "$root/usr/local/share/xcat-abi/app.txt")" = 'app 2' ]
    [ "$(cat "$root/usr/local/share/xcat-abi/zdep.txt")" = 'zdep 2' ]
    [ "$(cat "$root/usr/local/share/xcat-abi/adep.txt")" = 'adep 1' ]
    [ "$(cat "$root/usr/local/share/xcat-abi/mdep.txt")" = 'mdep 1' ]
    prior=$operation/managed.request
    live_stage verify-updated 2 "$selected_abi" "$prior"
    run verify-updated 0 inside /tools/helper -C /work/verify-updated/config local-verify /work/verify-updated/request /
    receipt "$operation/local-verify.result"
    grep -q '^changes[[:space:]]0$' "$operation/local-verify.result"
    inside /tools/pkg -C /dev/null query '%dn %dv' xcat-abi-app > "$case_root/updated-dependencies"
    printf 'xcat-abi-zdep 2\nxcat-abi-mdep 1\nxcat-abi-adep 1\n' > "$case_root/expected-updated-dependencies"
    cmp "$case_root/updated-dependencies" "$case_root/expected-updated-dependencies"
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_root/installed.updated"
    if [ "$name" = wildcard ]; then
        prior=$operation/managed.request
        for scope in verify update; do
            live_stage "mismatch-$scope" 2 FreeBSD:15:amd64 "$prior"
            run "mismatch-$scope" 1 inside /tools/helper -C "/work/mismatch-$scope/config" \
                "local-$scope" "/work/mismatch-$scope/request" /
            [ ! -e "$operation/local-$scope.result" ]
            [ ! -e "$operation/actions" ] && [ ! -e "$operation/after" ]
            receipt "$operation/local-$scope.rejected"
            printf 'format\txcat-freebsd-local-rejection-1\nscope\tlocal-%s\nplan-reference\t%s\nrequest-sha256\t%s\nprior-request-sha256\t%s\nconfig-sha256\t%s\npkg\t2.6.2\napply\tnot-started\noutcome\trejected\ncomplete\tyes\n' \
                "$scope" "$(awk -F '\t' '$1=="plan" {print $2}' "$operation/request")" \
                "$(sha256 -q "$operation/request")" "$(sha256 -q "$operation/prior-request")" \
                "$(sha256 -q "$operation/config")" > "$case_root/mismatch-$scope.expected"
            cmp "$case_root/mismatch-$scope.expected" "$operation/local-$scope.rejected"
            inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t' > "$case_root/mismatch-$scope.after"
            cmp "$case_root/installed.updated" "$case_root/mismatch-$scope.after"
            [ "$(cat "$root/usr/local/share/xcat-abi/app.txt")" = 'app 2' ]
        done
    fi
    umount "$active"
    active=
    count=$((count+1))
    printf 'ABI_CASE %s PASS\n' "$name"
done
printf 'ABI_CASES_COMPLETE %s\n' "$count"

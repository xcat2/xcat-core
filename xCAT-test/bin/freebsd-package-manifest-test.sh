#!/bin/sh

# Compare full-archive and full-manifest verification with native packages.
# Run only on a disposable FreeBSD node. Retain the workspace for evidence.
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
mkdir -m 0700 "$workspace" "$workspace/cases"
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

XCAT_FREEBSD_ABI_CASES=exact /bin/sh "$(dirname "$0")/freebsd-package-abi-test.sh" \
    "$workspace/reference" "$helper" > "$workspace/reference.stdout" 2> "$workspace/reference.stderr"
grep -q '^ABI_CASES_COMPLETE 1$' "$workspace/reference.stdout"
reference=$workspace/reference/cases/exact
root=$reference/target
active=$root/dev
mount -t devfs devfs "$active"
devfs -m "$active" rule apply hide
for device in null zero random urandom; do devfs -m "$active" rule apply path "$device" unhide; done

clean()
{
    env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C "$@"
}

inside()
{
    clean chroot "$root" "$@"
}

snapshot()
{
    inside /tools/pkg -C /dev/null query -a '%n %v %a %k %t'
    for component in app zdep adep mdep; do
        sha256 "$root/usr/local/share/xcat-abi/$component.txt"
    done
}

bind_request()
{
    chmod 0600 "$operation/request"
    while IFS= read -r row; do
        case "$row" in
        format*) printf 'format\txcat-freebsd-local-manifests-1\n' ;;
        plan*) printf '%s\n' "$row" ;;
        package*)
            id=$(printf '%s\n' "$row" | cut -f 2)
            printf '%s\t%s\t%s\n' "$row" "$(stat -f '%z' "$operation/archives/$id.manifest")" \
                "$(sha256 -q "$operation/archives/$id.manifest")"
            ;;
        *) exit 1 ;;
        esac
    done < "$operation/source-request" > "$operation/request"
    chmod 0400 "$operation/request"
}

stage()
{
    operation=$root/work/manifest-$name
    mkdir -m 0700 "$operation" "$operation/archives" "$operation/cache" "$operation/repos"
    cp -p "$root/work/verify-updated/request" "$operation/source-request"
    cp -p "$root/work/verify-updated/managed.request" "$operation/prior-request"
    chmod 0400 "$operation/prior-request"
    sed "s|/work/verify-updated/cache|/work/manifest-$name/cache|" \
        "$root/work/verify-updated/config" > "$operation/config"
    chmod 0400 "$operation/config"
    for id in p0 p1 p2 p3; do
        tar -xOf "$root/work/verify-updated/archives/$id.pkg" +MANIFEST > "$operation/archives/$id.manifest"
        chmod 0400 "$operation/archives/$id.manifest"
    done
    : > "$operation/request"
    bind_request
    chmod 0500 "$operation/archives"
}

change_manifest()
{
    sed "$1" "$operation/archives/p0.manifest" > "$case_root/changed.manifest"
    ! cmp -s "$case_root/changed.manifest" "$operation/archives/p0.manifest"
    cp "$case_root/changed.manifest" "$operation/archives/p0.manifest"
    chmod 0400 "$operation/archives/p0.manifest"
    bind_request
}

count=0
for name in equivalent comment file-digest dependency identity version bad-digest bad-size \
    file-bound total-bound missing extra symlink hardlink malformed update check install prior; do
    case_root=$workspace/cases/$name
    mkdir -m 0700 "$case_root"
    stage
    snapshot > "$case_root/before"
    expected=1
    diagnostic='local-check'
    mode=verify
    case "$name" in
    equivalent) expected=0 ;;
    comment)
        change_manifest 's/Native ABI fixture/Changed ABI fixture/g'
        diagnostic='same-version package lacks matching archive provenance or metadata' ;;
    file-digest)
        digest=$(sha256 -q "$root/usr/local/share/xcat-abi/app.txt")
        change_manifest "s/$digest/0000000000000000000000000000000000000000000000000000000000000000/g"
        diagnostic='same-version package lacks matching archive provenance or metadata' ;;
    dependency)
        change_manifest 's@misc/xcat-abi-mdep@misc/xcat-abi-other@g'
        diagnostic='same-version package lacks matching archive provenance or metadata' ;;
    identity)
        change_manifest 's/xcat-abi-app/xcat-abi-other/g'
        diagnostic='installed-operation archive metadata differs' ;;
    version)
        cp -p "$reference/install/request" "$operation/source-request"
        for id in p0 p1 p2 p3; do
            tar -xOf "$reference/install/archives/$id.pkg" +MANIFEST > "$operation/archives/$id.manifest"
        done
        bind_request
        diagnostic='required packages are not satisfied; verification cannot install or upgrade' ;;
    bad-digest) printf ' ' >> "$operation/archives/p0.manifest" ;;
    bad-size|file-bound|total-bound)
        awk -F '\t' -v OFS='\t' -v change="$name" '
            $1=="package" {
                if (change=="total-bound") $13=134217728
                else if ($2=="p0") $13=(change=="file-bound" ? 134217729 : $13+1)
            }
            {print}
            END {if (change=="total-bound") {$2="p4"; $4="xcat-abi-extra"; print}}
        ' "$operation/request" > "$case_root/changed.request"
        cp "$case_root/changed.request" "$operation/request"
        chmod 0400 "$operation/request"
        [ "$name" = bad-size ] || diagnostic='invalid local verification manifest size or digest'
        ;;
    missing) rm "$operation/archives/p0.manifest" ;;
    extra) cp -p "$operation/archives/p0.manifest" "$operation/archives/extra" ;;
    symlink)
        mv "$operation/archives/p0.manifest" "$case_root/manifest"
        ln -s "$case_root/manifest" "$operation/archives/p0.manifest" ;;
    hardlink) ln "$operation/archives/p0.manifest" "$case_root/manifest" ;;
    malformed)
        printf '{' > "$operation/archives/p0.manifest"
        bind_request
        diagnostic='cannot read sealed native verification manifest' ;;
    update|check|install) mode=$name; diagnostic='invalid local-check request format' ;;
    prior)
        cp "$operation/request" "$operation/prior-request"
        cp "$operation/source-request" "$operation/request"
        chmod 0400 "$operation/request" "$operation/prior-request"
        rm "$operation/archives/"*.manifest
        cp -p "$root/work/verify-updated/archives/"*.pkg "$operation/archives/"
        diagnostic='invalid local-check request format' ;;
    esac
    status=0
    case "$mode" in
    check)
        mkdir -m 0700 "$operation/db" "$operation/root"
        sed "s|$reference/check|$operation|g" "$reference/check/config" > "$operation/config"
        clean "$helper" -C "$operation/config" local-check "$operation/request" "$operation/root" \
            > "$case_root/stdout" 2> "$case_root/stderr" || status=$?
        [ -z "$(find "$operation/root" -mindepth 1 -print)" ]
        ;;
    install)
        target=$case_root/target
        mkdir -m 0755 "$target"
        (tar -C "$workspace/reference/base" -cpf - .; printf '%s\n' "$?" > "$case_root/copy.status") \
            | tar -C "$target" -xpf -
        [ "$(cat "$case_root/copy.status")" -eq 0 ]
        sed "s|$reference/target|$target|g" "$reference/install/config" > "$operation/config"
        clean "$helper" -C "$operation/config" local-install "$operation/request" "$target" \
            > "$case_root/stdout" 2> "$case_root/stderr" || status=$?
        [ -z "$(find "$target/var/db/pkg" -mindepth 1 -print)" ]
        ;;
    *)
        inside /tools/helper -C "/work/manifest-$name/config" "local-$mode" "/work/manifest-$name/request" / \
            > "$case_root/stdout" 2> "$case_root/stderr" || status=$?
        ;;
    esac
    printf '%s\n' "$status" > "$case_root/status"
    snapshot > "$case_root/after"
    cmp "$case_root/before" "$case_root/after"
    [ "$status" -eq "$expected" ]
    if [ "$expected" -eq 0 ]; then
        [ ! -s "$case_root/stderr" ]
        [ "$(stat -f '%u:%g:%l:%Lp' "$operation/local-verify.result")" = 0:0:1:600 ]
        grep -q '^complete[[:space:]]yes$' "$operation/local-verify.result"
        grep -q '^changes[[:space:]]0$' "$operation/local-verify.result"
        for member in before after managed.request; do
            cmp "$root/work/verify-updated/$member" "$operation/$member"
        done
    else
        grep -Fq "$diagnostic" "$case_root/stderr"
        [ ! -e "$operation/local-$mode.result" ] && [ ! -e "$operation/actions" ]
    fi
    count=$((count+1))
    printf 'MANIFEST_CASE %s PASS\n' "$name"
done
printf 'MANIFEST_CASES_COMPLETE %s\n' "$count"

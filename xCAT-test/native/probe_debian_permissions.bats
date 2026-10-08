#!/usr/bin/env bats

load '../bats/helpers/shell_source'

setup()
{
    if [ "$(uname -s)" != Linux ] || [ ! -f /etc/debian_version ]; then
        skip 'requires Debian package tools'
    fi
    if [ "$(id -u)" -eq 0 ]; then
        echo 'Run this test as an unprivileged user' >&2
        return 1
    fi
    for tool in perl dpkg-buildpackage dpkg-deb fakeroot reprepro bwrap; do
        command -v "$tool" >/dev/null || {
            echo "Required utility is unavailable: $tool" >&2
            return 1
        }
    done
    fixture="$(mktemp -d "${BATS_TMPDIR:-${TMPDIR:-/tmp}}/probe-permissions.XXXXXX")"
    checkout="$fixture/checkout"
    destination="$fixture/repository"
    payload="$fixture/payload"
    mkdir -p "$checkout" "$payload" "$fixture/home"
    for entry in builddebs.pl build-utils Version Release xCAT-probe perl-xCAT; do
        cp -a "$(repo_path "$entry")" "$checkout/"
    done
    mkdir -p "$checkout/xCAT-probe/lib/perl/xCAT"
    chmod 700 "$checkout/xCAT-probe/lib" "$checkout/xCAT-probe/lib/perl" \
        "$checkout/xCAT-probe/lib/perl/xCAT"
    chmod 600 "$checkout/xCAT-probe/lib/perl/"*.pm
    printf '1600000000\n' > "$checkout/Gitepoch"
    printf '%040d\n' 0 > "$checkout/Gitinfo"
}

teardown()
{
    if [ -n "${fixture:-}" ] && [ -d "$fixture" ]; then
        chmod -R u+rwX "$fixture"
        rm -rf "$fixture"
    fi
}

build_probe()
{
    cd "$checkout" || return 1
    run env -i HOME="$fixture/home" PATH=/usr/bin:/bin LC_ALL=C \
        perl builddebs.pl --package xCAT-probe --dist noble --release permissiontest \
        --dest "$destination"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }

    packages=("$destination"/debs/xcat-probe_*_all.deb)
    [ "${#packages[@]}" -eq 1 ]
    [ -f "${packages[0]}" ]
    run dpkg-deb -x "${packages[0]}" "$payload"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }

    prefix="$payload/opt/xcat"
    library_root="$prefix/probe/lib"
    library="$library_root/perl"
}

prepare_postinst()
{
    mkdir -p "$fixture/control" "$fixture/dpkg"
    run dpkg-deb -e "${packages[0]}" "$fixture/control"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    sandbox=(env -i PATH=/usr/bin:/bin LC_ALL=C bwrap
        --unshare-all --die-with-parent --new-session --ro-bind / /
        --dev /dev
        --tmpfs /opt --bind "$prefix" /opt/xcat
        --bind "$fixture/dpkg" /var/lib/dpkg)
}

run_postinst()
{
    run "${sandbox[@]}" /bin/sh "$fixture/control/postinst" "$@"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the Debian probe payload preserves library modes and contents" {
    build_probe
    [ "$(stat -c %a "$library_root")" = 755 ]
    [ "$(stat -c %a "$library")" = 755 ]
    [ "$(stat -c %a "$library/xCAT")" = 755 ]
    run find "$library_root" -type d ! -perm 0755 -print
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run find "$library_root" -type f ! -perm 0644 -print
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    for helper in CommandUtils GlobalDef NetworkUtils ServiceNodeUtils; do
        cmp "$(repo_path "perl-xCAT/xCAT/$helper.pm")" "$library/xCAT/$helper.pm"
    done
    cmp "$(repo_path xCAT-probe/lib/perl/probe_utils.pm)" "$library/probe_utils.pm"
}

@test "packaged probe commands load their helpers without root privileges" {
    build_probe
    for subcommand in code_template discovery osdeploy xcatmn; do
        [ "$(stat -c %a "$prefix/probe/subcmds/$subcommand")" = 755 ]
        run env -i PATH=/usr/bin:/bin XCATROOT="$prefix" \
            "$prefix/probe/subcmds/$subcommand" -T
        [ "$status" -eq 0 ] || { echo "$output"; return 1; }
        [[ "$output" =~ ^\[ok\][[:space:]]*: ]] || { echo "$output"; return 1; }
    done
}

@test "package configuration repairs the old directory mode idempotently" {
    build_probe
    prepare_postinst
    chmod 644 "$library/xCAT"
    run_postinst configure 2.19.0
    [ "$(stat -c %a "$library/xCAT")" = 755 ]
    run_postinst configure 2.19.0
    [ "$(stat -c %a "$library/xCAT")" = 755 ]
}

@test "package configuration preserves overrides and unrelated modes" {
    build_probe
    prepare_postinst
    chmod 644 "$library/xCAT"
    run "${sandbox[@]}" dpkg-statoverride --add root root 644 /opt/xcat/probe/lib/perl/xCAT
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run "${sandbox[@]}" dpkg-statoverride --list /opt/xcat/probe/lib/perl/xCAT
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$output" = 'root root 644 /opt/xcat/probe/lib/perl/xCAT' ]
    run_postinst configure 2.19.0
    [ "$(stat -c %a "$library/xCAT")" = 644 ]
    run "${sandbox[@]}" dpkg-statoverride --remove /opt/xcat/probe/lib/perl/xCAT
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    chmod 700 "$library/xCAT"
    run_postinst configure 2.19.0
    [ "$(stat -c %a "$library/xCAT")" = 700 ]
    mv "$library/xCAT" "$library/private"
    chmod 644 "$library/private"
    ln -s private "$library/xCAT"
    run_postinst configure 2.19.0
    [ "$(stat -c %a "$library/private")" = 644 ]
}

#!/usr/bin/env bats

load helpers/shell_source

setup() {
    [ "$(uname -s)" = Linux ] || skip 'requires Linux namespaces'
    local bwrap utility executable directory
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || return 1
    fixture="$BATS_TEST_TMPDIR/activation"
    mkdir -p "$fixture/bin" "$fixture/etc/yum.repos.d" "$fixture/apt"
    sandbox=(env -i "$bwrap" --unshare-all --die-with-parent --new-session
        --ro-bind / / --tmpfs /usr/bin --tmpfs /tmp --tmpfs /etc --tmpfs /var
        --proc /proc --dev /dev --uid 0 --gid 0
        --bind "$fixture" /tmp/fixture --bind "$fixture/etc" /etc
        --bind "$fixture/apt" /var/lib/apt/lists
        --setenv PATH /usr/bin --setenv LC_ALL C
        --ro-bind "$(repo_path xCAT-server/share/xcat/tools/go-xcat)" /tmp/go-xcat)
    # An inherited library-only setting must not disable the command.
    sandbox+=(--setenv GO_XCAT_LIBRARY_ONLY 1)
    for directory in /usr/sbin /sbin /bin; do
        [ -L "$directory" ] || sandbox+=(--tmpfs "$directory")
    done
    if [ ! -L /bin ]; then
        for utility in sh bash; do
            executable=$(PATH=/usr/bin:/bin type -P "$utility") || return 1
            sandbox+=(--ro-bind "$executable" "/bin/$utility")
        done
    fi
    local utilities=(bash sh awk cat comm cp cut dirname grep head id ln mkdir mktemp mv rm sed sleep sort tr wc xargs)
    if PATH=/usr/bin:/bin type -P coreutils >/dev/null; then utilities+=(coreutils); fi
    for utility in "${utilities[@]}"; do
        executable=$(PATH=/usr/bin:/bin type -P "$utility") || return 1
        sandbox+=(--ro-bind "$executable" "/usr/bin/$utility")
    done
    cat >"$fixture/bin/manager" <<'SH'
#!/bin/sh
operation=
for arg do
    case "$arg" in install|remove) operation=$arg; continue ;; esac
    [ -n "$operation" ] || continue
    case "$arg" in -*) continue ;; esac
    printf '%s %s\n' "$operation" "$arg" >> /tmp/fixture/transactions
done
[ "$operation" != install ] || exit 17
case "$*" in *repoquery*) printf '%s\n' fixture-package ;; esac
exit 0
SH
    cat >"$fixture/bin/rpm" <<'SH'
#!/bin/sh
case "$*" in
    '-q --quiet '*) grep -Fxq "$3" /tmp/fixture/installed ;;
    *) exit 0 ;;
esac
SH
    cat >"$fixture/bin/dpkg-query" <<'SH'
#!/bin/sh
if grep -Fxq "$3" /tmp/fixture/installed; then printf 'install ok installed'; else exit 1; fi
SH
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/apt-cache"
    printf '#!/bin/sh\nexit 22\n' >"$fixture/bin/curl"
    chmod +x "$fixture/bin/"*
    : >"$fixture/installed"
    : >"$fixture/transactions"
}

invoke() {
    local format=$1 architecture=$2 action=$3
    local debian_arch=$architecture
    local command=("${sandbox[@]}" --setenv HOSTTYPE "$architecture"
        --ro-bind "$fixture/bin/curl" /usr/bin/curl)
    if [ "$format" = rpm ]; then
        printf 'ID=almalinux\nVERSION_ID=8.10\n' >"$fixture/etc/os-release"
        command+=(--ro-bind "$fixture/bin/rpm" /usr/bin/rpm
            --ro-bind "$fixture/bin/manager" /usr/bin/dnf)
    else
        [ "$architecture" != x86_64 ] || debian_arch=amd64
        printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$debian_arch" >"$fixture/bin/dpkg"
        chmod +x "$fixture/bin/dpkg"
        mkdir -p "$fixture/etc/apt/sources.list.d"
        printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$fixture/etc/os-release"
        printf 'DISTRIB_CODENAME=noble\n' >"$fixture/etc/lsb-release"
        printf 'Package: fixture-package\nVersion: 1\n' >"$fixture/apt/test_xcat-core_dists_noble_main_binary-${debian_arch}_Packages"
        cp "$fixture/apt/test_xcat-core_dists_noble_main_binary-${debian_arch}_Packages" "$fixture/apt/test_xcat-dep_dists_noble_main_binary-${debian_arch}_Packages"
        command+=(--ro-bind "$fixture/bin/dpkg" /usr/bin/dpkg
            --ro-bind "$fixture/bin/dpkg-query" /usr/bin/dpkg-query
            --ro-bind "$fixture/bin/apt-cache" /usr/bin/apt-cache
            --ro-bind "$fixture/bin/manager" /usr/bin/apt-get)
    fi
    run "${command[@]}" /usr/bin/sh -c '
        /usr/bin/bash /tmp/go-xcat "$@"
        result=$?
        [ ! -f /tmp/go-xcat.log ] || cp /tmp/go-xcat.log /tmp/fixture/log
        exit "$result"
    ' go-xcat-test -y \
        --xcat-core=https://packages.example.test/core \
        --xcat-dep=https://packages.example.test/dep "$action"
}

check_uninstall() {
    local format=$1 selection=$2 name prefix=xCAT
    [ "$format" != deb ] || prefix=xcat
    local architectures=(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64 s390x)
    [ "$selection" != subset ] || architectures=(ppc64le riscv64)
    for name in "${architectures[@]}"; do
        [ "$format" != deb ] || name=${name//_/-}
        printf '%s-genesis-openembedded-%s\n' "$prefix" "$name"
    done >"$fixture/installed"
    printf 'unrelated-package\n' >>"$fixture/installed"
    invoke "$format" x86_64 uninstall
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    grep -v '^unrelated-package$' "$fixture/installed" | sed 's/^/remove /' | sort >"$fixture/expected"
    sort "$fixture/transactions" >"$fixture/actual"
    diff -u "$fixture/expected" "$fixture/actual"
}

check_install() {
    local format=$1 architecture=$2 prefix=xCAT legacy=ppc64 x86=x86_64
    if [ "$format" = deb ]; then prefix=xcat; legacy=ppc64el; x86=amd64; fi
    invoke "$format" "$architecture" install
    [ "$status" -eq 17 ] || { echo "$output" >&2; return 1; }
    local packages=("perl-$prefix" "$prefix-client" "$prefix" "$prefix-buildkit" "$prefix-server"
        elilo-xcat grub2-xcat ipmitool-xcat syslinux-xcat ipxe-xcat xnba-undi)
    if [ "$architecture" = riscv64 ]; then
        packages+=("$prefix-genesis-openembedded-riscv64")
    else
        packages+=("$prefix-genesis-scripts-$legacy" "$prefix-genesis-scripts-$x86"
            "$prefix-genesis-base-$legacy" "$prefix-genesis-base-$x86")
    fi
    [ "$format" != rpm ] || packages+=(initscripts)
    printf 'install %s\n' "${packages[@]}" | sort >"$fixture/expected"
    sort "$fixture/transactions" >"$fixture/actual"
    diff -u "$fixture/expected" "$fixture/actual" || {
        echo "$output" >&2
        [ ! -f "$fixture/log" ] || cat "$fixture/log" >&2
        return 1
    }
}

@test "RPM uninstall removes all installed OpenEmbedded architectures" { check_uninstall rpm all; }
@test "DEB uninstall removes all installed OpenEmbedded architectures" { check_uninstall deb all; }
@test "RPM uninstall excludes absent and unrelated packages" { check_uninstall rpm subset; }
@test "DEB uninstall excludes absent and unrelated packages" { check_uninstall deb subset; }
@test "RPM RISC-V installation selects OpenEmbedded and keeps other packages" { check_install rpm riscv64; }
@test "DEB RISC-V installation selects OpenEmbedded and keeps other packages" { check_install deb riscv64; }
@test "RPM x86 installation retains its legacy Genesis packages" { check_install rpm x86_64; }
@test "DEB x86 installation retains its legacy Genesis packages" { check_install deb x86_64; }

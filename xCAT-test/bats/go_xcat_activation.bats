#!/usr/bin/env bats

load helpers/script_sandbox

setup() {
    setup_script_sandbox awk cat comm cp cut dirname grep head id ln mkdir mktemp mv rm sed sleep sort tr wc xargs
    mkdir -p "$fixture/etc/yum.repos.d" "$fixture/tools"
    sandbox+=(--uid 0 --gid 0
        --ro-bind "$(repo_path xCAT-server/share/xcat/tools/go-xcat)" /run/go-xcat)
    # An inherited library-only setting must not disable the command.
    sandbox+=(--setenv GO_XCAT_LIBRARY_ONLY 1)
    cat >"$fixture/tools/manager" <<'SH'
#!/bin/sh
operation=
for arg do
    case "$arg" in install|remove) operation=$arg; continue ;; esac
    [ -n "$operation" ] || continue
    case "$arg" in -*) continue ;; esac
    printf '%s %s\n' "$operation" "$arg" >> /run/fixture/transactions
done
[ "$operation" != install ] || exit 17
case "$*" in *repoquery*) printf '%s\n' fixture-package ;; esac
exit 0
SH
    cat >"$fixture/tools/rpm" <<'SH'
#!/bin/sh
case "$*" in
    '-q --quiet '*) grep -Fxq "$3" /run/fixture/installed ;;
    *) exit 0 ;;
esac
SH
    cat >"$fixture/tools/dpkg-query" <<'SH'
#!/bin/sh
if grep -Fxq "$3" /run/fixture/installed; then printf 'install ok installed'; else exit 1; fi
SH
    cat >"$fixture/tools/apt-cache" <<'SH'
#!/bin/sh
[ "$1" = policy ] || exit 0
shift
for package do
    printf '%s:\n  Installed: (none)\n  Candidate: 1\n' "$package"
done
SH
    printf '#!/bin/sh\nexit 22\n' >"$fixture/bin/curl"
    chmod +x "$fixture/bin/curl" "$fixture/tools/"*
    : >"$fixture/installed"
    : >"$fixture/transactions"
}

invoke() {
    local format=$1 architecture=$2 action=$3
    local debian_arch=$architecture
    if [ "$format" = rpm ]; then
        printf 'ID=almalinux\nVERSION_ID=8.10\n' >"$fixture/etc/os-release"
        cp "$fixture/tools/rpm" "$fixture/bin/rpm"
        cp "$fixture/tools/manager" "$fixture/bin/dnf"
    else
        [ "$architecture" != x86_64 ] || debian_arch=amd64
        printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$debian_arch" >"$fixture/bin/dpkg"
        chmod +x "$fixture/bin/dpkg"
        mkdir -p "$fixture/etc/apt/sources.list.d" "$fixture/var/lib/apt/lists"
        printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$fixture/etc/os-release"
        printf 'DISTRIB_CODENAME=noble\n' >"$fixture/etc/lsb-release"
        printf 'Package: fixture-package\nVersion: 1\n' >"$fixture/var/lib/apt/lists/test_xcat-core_dists_noble_main_binary-${debian_arch}_Packages"
        cp "$fixture/var/lib/apt/lists/test_xcat-core_dists_noble_main_binary-${debian_arch}_Packages" "$fixture/var/lib/apt/lists/test_xcat-dep_dists_noble_main_binary-${debian_arch}_Packages"
        cp "$fixture/tools/dpkg-query" "$fixture/bin/dpkg-query"
        cp "$fixture/tools/apt-cache" "$fixture/bin/apt-cache"
        cp "$fixture/tools/manager" "$fixture/bin/apt-get"
    fi
    run "${sandbox[@]}" --setenv HOSTTYPE "$architecture" \
        timeout 30 bash /run/go-xcat -y \
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
        [ ! -f "$fixture/tmp/go-xcat.log" ] || cat "$fixture/tmp/go-xcat.log" >&2
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

#!/usr/bin/env bash

load 'helpers/genesis_sandbox'

setup_doxcat()
{
    setup_genesis_sandbox doxcat
    ib_address=80:00:00:48:fe:80:00:00:00:00:00:00:00:02:00:bb:cc:dd:ee:ff
    local utility fips library
    fips=$(repo_path xCAT-genesis-scripts/usr/lib/xcat/fips.sh)
    [ -r "$fips" ]
    mkdir -p "$fixture"/{etc/ssh,etc/pki/tls,real,links,addrs}
    for utility in bash sh cat cp awk grep sed sort tr tail rm wc cut head uname \
        timeout env ls mkdir touch readlink basename sleep; do
        cp -L "$(PATH=/usr/bin:/bin type -P "$utility")" "$fixture/bin/$utility"
    done
    if [ -x /usr/bin/coreutils ]; then
        cp -L /usr/bin/coreutils "$fixture/bin/coreutils"
    fi
    mv "$fixture/bin/sleep" "$fixture/real/sleep"
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/quiet"
    for utility in sleep rpcbind rpc.statd ssh-keygen lldpad chronyd; do
        cp "$fixture/bin/quiet" "$fixture/bin/$utility"
    done
    cp "$fixture/bin/quiet" "$fixture/bin/sshd"
    cp "$fixture/bin/quiet" "$fixture/bin/getcert"
    cp "$fixture/bin/quiet" "$fixture/bin/getdestiny"
    printf '#!/bin/sh\nexit 1\n' >"$fixture/bin/ipmitool"
    printf '#!/bin/sh\nprintf "rsyslogd 8.0\\n"\n' >"$fixture/bin/rsyslogd"
    cat >"$fixture/bin/openssl" <<'SH'
#!/bin/sh
printf 'fixture-public-key\n'
SH
    cat >"$fixture/bin/modprobe" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/modules
SH
    cat >"$fixture/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/messages
SH
    cat >"$fixture/bin/ip" <<'SH'
#!/bin/sh
case "$*" in
    'link'|'link show')
        cat /run/fixture/link-list
        if grep -Fxq ib_ipoib /run/fixture/modules; then
            cat /run/fixture/infiniband-links
        fi ;;
    '-o link show dev '*)
        [ ! -e "/run/fixture/links/$5.fail" ] || exit 17
        cat "/run/fixture/links/$5" ;;
    '-o addr show dev '*)
        [ ! -e "/run/fixture/addrs/$5.fail" ] || exit 19
        cat "/run/fixture/addrs/$5" ;;
    '-4 -o a show dev '*) printf '2: %s inet 192.0.2.20/24 scope global\n' "$6" ;;
    *) printf 'unexpected ip %s\n' "$*" >&2; exit 97 ;;
esac
SH
    cat >"$fixture/bin/ethtool" <<'SH'
#!/bin/sh
printf 'Link detected: yes\n'
SH
    cat >"$fixture/bin/dhclient" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/dhcp
SH
    cat >"$fixture/bin/finish" <<'SH'
#!/bin/sh
printf '%s\n' "$DEVICE" > /run/fixture/bootnic
printf '%s\n' "$NICSTOBRINGUP" > /run/fixture/selected
set -- $NICSTOBRINGUP
expected=$((2 + 2 * $#))
tries=0
while [ "$(wc -l </run/fixture/dhcp)" -lt "$expected" ] && [ "$tries" -lt 1000 ]; do
    /run/fixture/real/sleep 0.01
    tries=$((tries + 1))
done
SH
    printf '#!/bin/sh\nprintf "runcmd=exit 0\\n"\n' >"$fixture/bin/nextdestiny"
    chmod +x "$fixture/bin/"*
    : >"$fixture/etc/rsyslog.conf"
    : >"$fixture/link-list"
    : >"$fixture/infiniband-links"
    : >"$fixture/modules"
    : >"$fixture/dhcp"
    printf '0\n' >"$fixture/fips_enabled"
    sandbox+=(--ro-bind "$fixture/bin" /usr/bin
        --tmpfs /proc/sys
        --ro-bind "$fixture/fips_enabled" /proc/sys/crypto/fips_enabled
        --tmpfs /usr/lib)
    if [ ! -L /usr/sbin ]; then
        sandbox+=(--ro-bind "$fixture/bin" /usr/sbin)
    fi
    if [ ! -L /bin ]; then
        sandbox+=(--ro-bind "$fixture/bin" /bin)
    fi
    if [ ! -L /sbin ]; then
        sandbox+=(--ro-bind "$fixture/bin" /sbin)
    fi
    for library in /usr/lib/*; do
        [ "${library##*/}" = xcat ] && continue
        sandbox+=(--ro-bind "$library" "$library")
    done
    sandbox+=(--ro-bind "$fips" /usr/lib/xcat/fips.sh
        --setenv PATH /usr/bin:/usr/sbin
        --setenv destiny runcmd=/run/fixture/bin/finish)
}

add_doxcat_link()
{
    local nic=$1 flags=$2 kind=${3:-ether} address=${4:-00:11:22:33:44:55}
    mkdir -p "$fixture/sys/class/net/$nic"
    printf '2: %s: <%s> mtu 1500 state UP\n    link/%s %s\n' \
        "$nic" "$flags" "$kind" "$address" >"$fixture/links/$nic"
    if [ "$kind" = infiniband ]; then
        cat "$fixture/links/$nic" >>"$fixture/infiniband-links"
    else
        cat "$fixture/links/$nic" >>"$fixture/link-list"
    fi
    : >"$fixture/addrs/$nic"
}

assert_doxcat_dhcp()
{
    local nic
    printf '%s\n' "$@" | sed '/^$/d' | sort >"$fixture/expected-selection"
    tr ' ' '\n' <"$fixture/selected" | sed '/^$/d' | sort >"$fixture/actual-selection"
    run diff -u "$fixture/expected-selection" "$fixture/actual-selection"
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    : >"$fixture/expected-dhcp"
    for nic in "$(cat "$fixture/bootnic")" "$@"; do
        printf '%s\n' "-cf /etc/dhclient.conf -pf /var/run/dhclient.$nic.pid $nic" \
            "-6 -pf /var/run/dhclient6.$nic.pid $nic -lf /var/lib/dhclient/dhclient6.leases" \
            >>"$fixture/expected-dhcp"
    done
    sort "$fixture/expected-dhcp" >"$fixture/expected-sorted"
    sort "$fixture/dhcp" >"$fixture/actual-sorted"
    run diff -u "$fixture/expected-sorted" "$fixture/actual-sorted"
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
}

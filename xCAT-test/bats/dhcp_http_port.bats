#!/usr/bin/env bats

@test "ISC subnet and node callers preserve their HTTP port defaults" {
    [ -n "$BATS_TEST_TMPDIR" ] || return 1
    for port in null '""' 0 '"0"' '"80"' '"080"' '"8080"'; do
        fixture=$(mktemp -d "$BATS_TEST_TMPDIR/isc.XXXXXX")
        mkdir -p "$fixture/etc/sysconfig" "$fixture/tftp" "$fixture/config"
        printf 'DHCPDARGS=""\n' > "$fixture/etc/sysconfig/dhcpd"
        run bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
            --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
            --bind "$fixture" /tmp/fixture --bind "$fixture/etc" /etc --chdir /tmp/fixture \
            perl /tmp/source/xCAT-test/bats/fixtures/dhcp-http.pl "$port"
        [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
        case "$port" in
            '"080"') suffix=:080 ;;
            '"8080"') suffix=:8080 ;;
            *) suffix= ;;
        esac
        grep -Fq "option cumulus-provision-url \"http://192.0.2.1$suffix/install/postscripts/cumulusztp\";" "$fixture/dhcpd.conf"
        grep -Fq "http://192.0.2.1$suffix/tftpboot/petitboot/cn1" "$fixture/omshell"
    done
}

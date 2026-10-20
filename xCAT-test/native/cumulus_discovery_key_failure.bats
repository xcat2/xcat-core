#!/usr/bin/env bats

load '../bats/helpers/script_sandbox'

setup()
{
    setup_script_sandbox dirname cat grep tail awk mkdir
    mkdir -p "$fixture/etc/xcat" "$fixture/etc/pki/tls" "$fixture/var/lib/dhcp"
    printf '%s\n' 'option cumulus-provision-url "http://192.0.2.1/install/postscripts/cumulusztp";' \
        >"$fixture/var/lib/dhcp/dhclient.eth0.leases"
    cat >"$fixture/bin/openssl" <<'SH'
#!/bin/sh
printf 'attempted\n' >/run/fixture/key-attempt
exit 1
SH
    cat >"$fixture/bin/logger" <<'SH'
#!/bin/sh
exit 0
SH
    cat >"$fixture/bin/socat" <<'SH'
#!/bin/sh
printf 'started\n' >/run/fixture/listener-started
exit 0
SH
    chmod 0755 "$fixture/bin/openssl" "$fixture/bin/logger" "$fixture/bin/socat"
    sandbox+=(--ro-bind "$(repo_path xCAT/postscripts)" /tmp/postscripts)
}

@test "Cumulus discovery stops before starting a listener when key generation fails" {
    run "${sandbox[@]}" /usr/bin/timeout --kill-after=5 45 \
        /bin/bash /tmp/postscripts/documulusdiscovery
    printf '%s\n' "$output"
    [ "$status" -eq 1 ]
    [ -f "$fixture/key-attempt" ]
    [ ! -e "$fixture/tmp/helper.socat.sh" ]
    [ ! -e "$fixture/listener-started" ]
}

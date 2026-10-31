#!/usr/bin/env bats

load 'helpers/genesis_sandbox'

setup()
{
    setup_genesis_sandbox dodiscovery
    local fips library
    fips=$(repo_path xCAT-genesis-scripts/usr/lib/xcat/fips.sh)
    [ -r "$fips" ]
    type -P gzip >/dev/null || {
        echo 'Install gzip to read the discovery request' >&2
        return 1
    }
    dmi="$fixture/sys/devices/virtual/dmi/id"
    mkdir -p "$dmi" "$fixture/real"
    printf 'Example Server\n' >"$dmi/product_name"
    printf 'Example Inc.\n' >"$dmi/sys_vendor"
    printf 'EX0001\n' >"$dmi/product_serial"
    printf 'xcatd=192.0.2.1:3001\n' >"$fixture/cmdline"
    cp -L "$(PATH=/usr/bin:/bin type -P sleep)" "$fixture/real/sleep"
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/minixcatd.awk"
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/logger"
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/ip"
    printf '#!/bin/sh\nexit 1\n' >"$fixture/bin/ipmitool"
    cat >"$fixture/bin/openssl" <<'SH'
#!/bin/sh
case "$1" in
    dgst) printf 'signature\n' >"$4" ;;
    enc) printf 'c2lnbmF0dXJl\n' ;;
    *) printf 'fixture-public-key\n' ;;
esac
SH
    cat >"$fixture/bin/udpcat.awk" <<'SH'
#!/bin/sh
cat >/run/fixture/sent.tmp
mv /run/fixture/sent.tmp /run/fixture/sent.gz
SH
    # The discovery loop sends again until /restart exists, so the pause after the first send ends it.
    cat >"$fixture/bin/sleep" <<'SH'
#!/bin/sh
tries=0
while [ ! -s /run/fixture/sent.gz ] && [ "$tries" -lt 1000 ]; do
    /run/fixture/real/sleep 0.01
    tries=$((tries + 1))
done
kill -TERM "$PPID"
SH
    chmod +x "$fixture/bin/"*
    sandbox+=(--tmpfs /usr/lib)
    for library in /usr/lib/*; do
        [ "${library##*/}" = xcat ] && continue
        sandbox+=(--ro-bind "$library" "$library")
    done
    sandbox+=(--ro-bind "$fips" /usr/lib/xcat/fips.sh)
}

reported_uuids()
{
    gzip -dc "$fixture/sent.gz" | sed -n 's|^<uuid>\(.*\)</uuid>$|\1|p'
}

@test 'discovery reports the system UUID that the kernel prints' {
    printf '12345678-1234-4bcd-9876-1234567890ab\n' >"$dmi/product_uuid"
    run_genesis 143
    run reported_uuids
    [ "$status" -eq 0 ]
    [ "$output" = '12345678-1234-4bcd-9876-1234567890ab' ]
}

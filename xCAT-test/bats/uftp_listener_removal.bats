#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'package scriptlets run in a Linux sandbox'
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the package removal test' >&2
        return 1
    }
    fixture="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$fixture/bin" "$fixture/opt/xcat/share/xcat/scripts"
    cat >"$fixture/bin/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/tmp/fixture/systemctl.log
SH
    cat >"$fixture/opt/xcat/share/xcat/scripts/xcatd-init-compat" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/tmp/fixture/compat.log
exit 0
SH
    chmod +x "$fixture/bin/systemctl" "$fixture/opt/xcat/share/xcat/scripts/xcatd-init-compat"
    awk '/^%preun$/ { copy = 1; next } copy && !/^%/' "$(repo_path xCAT-server/xCAT-server.spec)" >"$fixture/preun"
    [ -s "$fixture/preun" ]
    sandbox=("$bwrap" --unshare-all --die-with-parent --new-session
        --ro-bind / / --tmpfs /tmp --tmpfs /opt --tmpfs /usr/sbin --proc /proc --dev /dev
        --bind "$fixture" /tmp/fixture --bind "$fixture/opt/xcat" /opt/xcat
        --ro-bind "$(repo_path xCAT-server/debian/prerm)" /tmp/prerm
        --setenv PATH /tmp/fixture/bin:/usr/bin:/bin --setenv RPM_INSTALL_PREFIX0 /opt/xcat)
}

@test 'RPM erase stops and disables the UFTP listener' {
    run "${sandbox[@]}" /bin/bash /tmp/fixture/preun 0
    [ "$status" -eq 0 ]
    grep -qx 'stop xcatd.service' "$fixture/systemctl.log"
    grep -qx 'disable --now xcat-uftp-listener.service' "$fixture/systemctl.log"
}

@test 'RPM upgrade leaves the UFTP listener alone' {
    run "${sandbox[@]}" /bin/bash /tmp/fixture/preun 1
    [ "$status" -eq 0 ]
    if grep -q uftp "$fixture/systemctl.log" 2>/dev/null; then
        echo 'an upgrade touched the listener'
        return 1
    fi
}

@test 'Debian removal stops and disables the UFTP listener' {
    run "${sandbox[@]}" /bin/sh /tmp/prerm remove
    [ "$status" -eq 0 ]
    grep -qx 'stop xcatd.service' "$fixture/systemctl.log"
    grep -qx 'disable --now xcat-uftp-listener.service' "$fixture/systemctl.log"
}

@test 'Debian upgrade leaves the UFTP listener alone' {
    run "${sandbox[@]}" /bin/sh /tmp/prerm upgrade 2.19.1
    [ "$status" -eq 0 ]
    if grep -q uftp "$fixture/systemctl.log" 2>/dev/null; then
        echo 'an upgrade touched the listener'
        return 1
    fi
}

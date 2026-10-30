#!/usr/bin/env bats
#
# The privilege separation directory sshd needs, at the moment doxcat starts sshd.
#
# Debian and Ubuntu build sshd with --with-privsep-path=/run/sshd. The Genesis image carries
# /run and not /run/sshd, so sshd exited with "Missing privilege separation directory" and the
# node answered no ssh at all. Every legacy Genesis case that reaches a booted node over xdsh
# failed on "Connection refused" while sequential discovery, which needs no ssh, passed.
#
# doxcat already did this for the other family -- it creates /usr/share/empty.sshd, the EL
# privsep path -- so this is the same line for Debian. The assertions are what SSHD IMPOSES,
# read at the moment sshd runs: the path is a directory, its owner is the user that will run
# sshd, and it is not group or world writable. sshd refuses a loose mode with the same message
# as an absent directory, so a wrong mode is indistinguishable from the bug.
#
# Read from inside the sandbox on purpose. /run there is a tmpfs, exactly as it is on a running
# system, so a directory made before that mount -- or baked into the image -- is not there when
# sshd starts and cannot be seen from outside afterwards.

load 'helpers/doxcat_sandbox'

PRIVSEP_PATHS='/run/sshd /var/run/sshd'

# Record what each privsep path looks like AT THE MOMENT sshd runs.
#
# doxcat runs sshd as /usr/sbin/sshd, an absolute path, so a stub on PATH is never reached and
# the recorder is bound over that path instead. Recording from a later PATH command instead --
# openssl is the next one -- cannot see the ORDER: moving the directories after the sshd line
# then passes, which is the one mutation that matters most here.
record_privsep()
{
    local stub="${BATS_TEST_TMPDIR}/sshd-recorder"

    cat >"$stub" <<SH
#!/bin/sh
for d in $PRIVSEP_PATHS; do
    if [ -d "\$d" ]; then
        # ls, not stat: the sandbox carries only the utilities the helper copies, and a
        # command missing there silently does nothing. Field 1 is the mode string, field 3
        # the owner, numeric because ls has no passwd lookup here.
        ls -ld "\$d" | awk '{ printf "%s dir %s %s\\n", "'"\$d"'", \$1, \$3 }' \\
            >>/run/fixture/sshd-privsep
    else
        printf '%s absent\n' "\$d" >>/run/fixture/sshd-privsep
    fi
done
exit 0
SH
    chmod 0755 "$stub"
    sandbox+=(--ro-bind "$stub" /usr/sbin/sshd)
}

seen()
{
    local path="$1"
    awk -v p="$path" '$1 == p { print; exit }' "$fixture/sshd-privsep"
}

@test "doxcat makes every privilege separation directory before it starts sshd" {
    setup_doxcat
    record_privsep
    add_doxcat_link eth0 BROADCAST,MULTICAST,UP ether 02:bb:cc:dd:ee:ff
    run_genesis 0 --setenv BOOTIF 01-02-bb-cc-dd-ee-ff

    # The recording ran, so it happened one statement after sshd was started.
    [ -s "$fixture/sshd-privsep" ]

    for path in $PRIVSEP_PATHS; do
        local line mode owner
        line=$(seen "$path")
        [ -n "$line" ]
        [ "$(printf '%s\n' "$line" | cut -d' ' -f2)" = dir ]
        mode=$(printf '%s\n' "$line" | cut -d' ' -f3)
        owner=$(printf '%s\n' "$line" | cut -d' ' -f4)
        # Owned by whoever runs sshd: root in Genesis, the invoking user here. ls in
        # the sandbox has no passwd lookup, so the owner comes back numeric.
        [ "$owner" = "$(id -u)" ]
        # sshd refuses a group or world writable privsep directory. Positions 6 and 9 of the
        # mode string are the group and other write bits.
        [ "$(printf '%s\n' "$mode" | cut -c6)" = - ]
        [ "$(printf '%s\n' "$mode" | cut -c9)" = - ]
    done
}

@test "a privilege separation directory left group writable is corrected, not kept" {
    # The directory can already exist from an earlier boot with a mode sshd will not accept,
    # and that failure prints the same message as an absent one. So the mode is set whether or
    # not doxcat had to create the directory.
    setup_doxcat
    record_privsep
    add_doxcat_link eth0 BROADCAST,MULTICAST,UP ether 02:bb:cc:dd:ee:ff
    # /var is bound from the fixture, so this one survives into the sandbox.
    mkdir -p "$fixture/var/run/sshd"
    chmod 0777 "$fixture/var/run/sshd"
    run_genesis 0 --setenv BOOTIF 01-02-bb-cc-dd-ee-ff

    local mode
    mode=$(printf '%s\n' "$(seen /var/run/sshd)" | cut -d' ' -f3)
    [ -n "$mode" ]
    [ "$(printf '%s\n' "$mode" | cut -c6)" = - ]
    [ "$(printf '%s\n' "$mode" | cut -c9)" = - ]
}

@test "every command doxcat runs resolves inside the sandbox" {
    # The sandbox curates PATH and does NOT include /usr/bin, so a command it does not copy
    # resolves to nothing. That fails silently: doxcat's chmod did nothing under test for as
    # long as this sandbox has existed, and an assertion about a mode could never pass. The
    # mode half of the privsep fix was unmeasurable until chmod was added to the helper.
    #
    # Derived, not a list: bash calls command_not_found_handle for anything it cannot resolve,
    # so this records whatever doxcat actually invokes and goes missing. A list here would go
    # stale the next time doxcat gains a command.
    #
    # Its reach is the commands doxcat runs ON THE PATH THIS TEST DRIVES, which is not every
    # command in the script -- a branch this boot does not take is not covered. It is a floor,
    # not a completeness check on the helper's list.
    setup_doxcat
    record_privsep
    local env_file="${BATS_TEST_TMPDIR}/bash_env"
    cat >"$env_file" <<'SH'
command_not_found_handle()
{
    printf '%s\n' "$1" >>/run/fixture/not-found
    return 127
}
SH
    sandbox+=(--ro-bind "$env_file" /run/bash_env --setenv BASH_ENV /run/bash_env)
    add_doxcat_link eth0 BROADCAST,MULTICAST,UP ether 02:bb:cc:dd:ee:ff
    run_genesis 0 --setenv BOOTIF 01-02-bb-cc-dd-ee-ff

    # The handler was installed, so an absence would have been recorded.
    [ -s "$fixture/sshd-privsep" ]
    if [ -e "$fixture/not-found" ]; then
        printf 'doxcat runs commands the sandbox does not provide:\n%s\n' \
            "$(sort -u "$fixture/not-found")" >&2
        return 1
    fi
}

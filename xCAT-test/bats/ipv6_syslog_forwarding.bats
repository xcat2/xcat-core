#!/usr/bin/env bats
#
# rsyslog and syslog-ng both take a forwarding target after "@", and neither
# parses a bare IPv6 literal there: rsyslog needs the address in brackets, and
# syslog-ng needs the udp6() driver instead of udp(). The syslog postscript and
# the initrd rsyslog launcher each carry a formatter for this.

load 'helpers/shell_source'

load_syslog_helpers()
{
    local file lib
    file="$(require_repo_file 'xCAT/postscripts/syslog')"
    lib="${BATS_TEST_TMPDIR}/syslog.sh"
    { extract_shell_function "$file" 'format_syslog_forward_target'
      extract_shell_function "$file" 'syslog_ng_udp_driver'; } >"$lib" || return 1
    # shellcheck disable=SC1090
    . "$lib"
}

@test "an IPv6 forwarding target is bracketed for rsyslog" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '2001:db8::1')" = '[2001:db8::1]' ]
}

@test "an IPv4 target and a hostname are passed through unchanged" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '192.0.2.10')" = '192.0.2.10' ]
    [ "$(format_syslog_forward_target 'mn01')" = 'mn01' ]
}

# A COLON DOES NOT MEAN IPv6. site.master may carry a port -- xcat-core/#7975 sets
# MASTER=127.0.0.1:1515 for its own forwarding case -- and an IPv4 or hostname target with a port
# has exactly one colon, while an IPv6 literal has at least two. Bracketing on any colon rendered
# @[127.0.0.1:1515], which rsyslog does not accept, and sent syslog-ng to udp6 for an IPv4 peer.
@test "a target with a port is not mistaken for an IPv6 literal" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '127.0.0.1:1515')" = '127.0.0.1:1515' ]
    [ "$(format_syslog_forward_target '192.0.2.10:514')" = '192.0.2.10:514' ]
    [ "$(format_syslog_forward_target 'mn01:514')" = 'mn01:514' ]
    [ "$(syslog_ng_udp_driver '127.0.0.1:1515')" = 'udp' ]
    [ "$(syslog_ng_udp_driver 'mn01:514')" = 'udp' ]
}

@test "a compressed IPv6 literal is still bracketed and still udp6" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '::1')" = '[::1]' ]
    [ "$(syslog_ng_udp_driver '::1')" = 'udp6' ]
    [ "$(syslog_ng_udp_driver '2001:db8::1')" = 'udp6' ]
}

@test "an already-bracketed target with a port is left alone" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '[2001:db8::1]:514')" = '[2001:db8::1]:514' ]
}

@test "an already-bracketed target is not bracketed twice" {
    load_syslog_helpers
    [ "$(format_syslog_forward_target '[2001:db8::1]')" = '[2001:db8::1]' ]
}

@test "syslog-ng selects udp6 for an IPv6 target and udp otherwise" {
    load_syslog_helpers
    [ "$(syslog_ng_udp_driver '2001:db8::1')" = 'udp6' ]
    [ "$(syslog_ng_udp_driver '192.0.2.10')" = 'udp' ]
    [ "$(syslog_ng_udp_driver 'mn01')" = 'udp' ]
}

@test "the initrd rsyslog launcher writes a bracketed forwarding line" {
    local file lib template
    file="$(require_repo_file 'xCAT-server/share/xcat/netboot/rh/dracut_105/patch/syslog/rsyslogd-start.sh')"
    lib="${BATS_TEST_TMPDIR}/rsyslogd.sh"
    { extract_shell_function "$file" 'format_syslog_server'
      extract_shell_function "$file" 'rsyslog_config'; } >"$lib"
    # shellcheck disable=SC1090
    . "$lib"

    template="${BATS_TEST_TMPDIR}/rsyslog.conf"
    printf '# template\n' >"$template"

    run rsyslog_config '2001:db8::1' "$template" 'kern.*'
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = 'kern.* @[2001:db8::1]' ]

    run rsyslog_config '192.0.2.10' "$template" 'kern.*'
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = 'kern.* @192.0.2.10' ]
}

# The initrd launcher carries its OWN copy of the rule -- it runs inside the dracut initramfs and
# cannot source the postscript -- so the port case has to be held down twice.
@test "the initrd launcher does not mistake a port for an IPv6 literal" {
    local file lib template
    file="$(require_repo_file 'xCAT-server/share/xcat/netboot/rh/dracut_105/patch/syslog/rsyslogd-start.sh')"
    lib="${BATS_TEST_TMPDIR}/rsyslogd.sh"
    { extract_shell_function "$file" 'format_syslog_server'
      extract_shell_function "$file" 'rsyslog_config'; } >"$lib"
    # shellcheck disable=SC1090
    . "$lib"

    template="${BATS_TEST_TMPDIR}/rsyslog.conf"
    printf '# template\n' >"$template"

    run rsyslog_config '127.0.0.1:1515' "$template" 'kern.*'
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = 'kern.* @127.0.0.1:1515' ]

    run rsyslog_config '::1' "$template" 'kern.*'
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = 'kern.* @[::1]' ]
}

@test "the initrd launcher logs locally when no server is given" {
    local file lib template
    file="$(require_repo_file 'xCAT-server/share/xcat/netboot/rh/dracut_105/patch/syslog/rsyslogd-start.sh')"
    lib="${BATS_TEST_TMPDIR}/rsyslogd.sh"
    { extract_shell_function "$file" 'format_syslog_server'
      extract_shell_function "$file" 'rsyslog_config'; } >"$lib"
    # shellcheck disable=SC1090
    . "$lib"

    template="${BATS_TEST_TMPDIR}/rsyslog.conf"
    printf '# template\n' >"$template"

    run rsyslog_config '' "$template" 'kern.*'
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = 'kern.* /var/log/messages' ]
}

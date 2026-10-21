#!/usr/bin/env bats
#
# The classifier that decides which SELinux denials xCAT is answerable for. The records
# below are real: they were captured on an enforcing AlmaLinux 10 management node while a
# compute node was provisioned.

load 'helpers/shell_source'

setup()
{
    . "$(repo_path 'xCAT-test/autotest/testcase/commoncmd/selinux_avc_check.sh')"
}

classify()
{
    printf '%s\n' "$@" | selinux_avc_classify
}

count_kept()
{
    printf '%s\n' "$@" | selinux_avc_classify | grep -c '^type='
}

# httpd serving /tftpboot through the xcat.conf AliasMatch. This is the one the xcat
# policy module exists for, so a denial here is xCAT's.
XCAT_RECORD='type=AVC msg=audit(1759000000.111:222): avc:  denied  { getattr } for  pid=1234 comm="httpd" path="/tftpboot/xcat/xnba.kpxe" dev="vda2" ino=55 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:shadow_t:s0 tclass=file permissive=0'

# httpd asking for net_admin on itself, every ten seconds, on an idle node. 817 of 1034
# denials on one node in one day were this shape.
TIMER_RECORD='type=AVC msg=audit(1759000001.222:333): avc:  denied  { net_admin } for  pid=2345 comm="httpd" scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:system_r:httpd_t:s0 tclass=capability permissive=0'

# An ordinary ssh login. cluster-test.pl makes one on every step.
SSH_RECORD='type=AVC msg=audit(1759000002.333:444): avc:  denied  { siginh } for  pid=3456 comm="sshd" scontext=system_u:system_r:sshd_t:s0-s0:c0.c1023 tcontext=system_u:system_r:sshd_session_t:s0-s0:c0.c1023 tclass=process permissive=0'

@test "a denial on an xCAT directory is kept" {
    run classify "$XCAT_RECORD"
    [ "$status" -eq 0 ]
    [[ "$output" == *'/tftpboot/xcat/xnba.kpxe'* ]]
}

@test "the httpd net_admin timer is not kept" {
    run classify "$TIMER_RECORD"
    [ -z "$output" ]
}

@test "an ssh login denial is not kept" {
    run classify "$SSH_RECORD"
    [ -z "$output" ]
}

@test "one xCAT denial among the noise is found and counted once" {
    run count_kept "$TIMER_RECORD" "$XCAT_RECORD" "$SSH_RECORD" "$TIMER_RECORD"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "a window of noise alone is kept empty" {
    run classify "$TIMER_RECORD" "$SSH_RECORD"
    [ -z "$output" ]
}

@test "a denial by an xCAT program is kept whatever the path" {
    local record='type=AVC msg=audit(1759000003.444:555): avc:  denied  { read } for  pid=4567 comm="genimage" name="dracut.conf" scontext=system_u:system_r:unconfined_service_t:s0 tcontext=system_u:object_r:etc_t:s0 tclass=file permissive=0'
    run classify "$record"
    [ "$status" -eq 0 ]
    [[ "$output" == *'comm="genimage"'* ]]
}

@test "a program whose name merely contains a kept word is not matched by accident" {
    local record='type=AVC msg=audit(1759000004.555:666): avc:  denied  { execute } for  pid=5678 comm="systemd-udevd" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:bin_t:s0 tclass=file permissive=0'
    run classify "$record"
    [ -z "$output" ]
}

@test "the report refuses a call with no start time" {
    run "$(repo_path 'xCAT-test/autotest/testcase/commoncmd/selinux_avc_check.sh')"
    [ "$status" -eq 2 ]
}

@test "the report refuses a checkpoint call with no file" {
    run selinux_avc_since ""
    [ "$status" -eq 2 ]
    run selinux_avc_init ""
    [ "$status" -eq 2 ]
}

@test "an empty window with nothing today is a usage error, not a clean answer" {
    run selinux_avc_report "01/01/1970 00:00:00"
    [ "$status" -eq 2 ]
    [[ "$output" == *"SEARCHED=0"* ]]
    [[ "$output" == *"none today"* ]]
}

# The guard the checkpoint form needs. ausearch answers with records, with
# '<no matches>', or with nothing once it has read to the end of the log. An
# error message is none of those, and counting it reports a clean window.
@test "an ausearch error message is not a clean window" {
    run selinux_avc_count "Invalid start time (10/21/2026 20:59:08). Hour, Minute, and Second are required."
    [ "$status" -eq 2 ]
    [[ "$output" == *"neither a record nor"* ]]
}

@test "a log read to its end is a clean window" {
    run selinux_avc_count "<no matches>"
    [ "$status" -eq 0 ]
    [ "$output" = "AVC=0 XCAT_AVC=0" ]
    run selinux_avc_count ""
    [ "$status" -eq 0 ]
    [ "$output" = "AVC=0 XCAT_AVC=0" ]
}

@test "an xCAT denial after the checkpoint is kept" {
    ausearch() { printf '%s\n' "$XCAT_RECORD"; }
    run selinux_avc_since /tmp/selinux_avc_check_bats.ck
    [ "$status" -eq 1 ]
    [[ "$output" == *"AVC=1 XCAT_AVC=1"* ]]
    [[ "$output" == *'/tftpboot/xcat/xnba.kpxe'* ]]
}

@test "noise after the checkpoint is counted and not kept" {
    ausearch() { printf '%s\n' "$TIMER_RECORD"; }
    run selinux_avc_since /tmp/selinux_avc_check_bats.ck
    [ "$status" -eq 0 ]
    [ "$output" = "AVC=1 XCAT_AVC=0" ]
}

# A checkpoint that reads no record is not a quiet node: ausearch writes no
# checkpoint file, so the next call reads the whole log.
@test "the baseline counts the records the checkpoint consumed" {
    ausearch() { printf '%s\n' "$TIMER_RECORD" "$SSH_RECORD"; }
    run selinux_avc_init /tmp/selinux_avc_check_bats.ck
    [ "$status" -eq 0 ]
    [ "$output" = "BASELINE=2" ]
    ausearch() { printf '%s\n' "<no matches>"; }
    run selinux_avc_init /tmp/selinux_avc_check_bats.ck
    [ "$output" = "BASELINE=0" ]
}

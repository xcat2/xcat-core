#!/usr/bin/env bats
#
# doxcat reads the management node address and port out of the xcatd= kernel argument. An IPv6
# address holds colons, so splitting "<address>:<port>" on the colon gave address 2001 and port
# db8, and the node never reached xcatd. destiny.pm now brackets an IPv6 address.

load 'helpers/shell_source'

setup()
{
    DOXCAT="$(repo_path 'xCAT-genesis-scripts/usr/bin/doxcat')"
    [ -r "$DOXCAT" ] || skip "$DOXCAT is required"
    export DOXCAT
}

# Run only doxcat's cmdline parse loop against a given /proc/cmdline, and print what it decided.
# The loop is extracted by line range rather than re-implemented, so the test reads the shipped
# code; a change to the loop that breaks parsing shows up here.
parse_xcatd()
{
    local cmdline="$1" dir="${BATS_TEST_TMPDIR}"
    printf '%s\n' "$cmdline" >"$dir/cmdline"
    sed -n '/^XCATPORT=3001$/,/^export XCATDEST$/p' "$DOXCAT" >"$dir/loop.sh"
    [ -s "$dir/loop.sh" ] || { echo "could not extract the parse loop" >&2; return 1; }
    sed -i "s|cat /proc/cmdline|cat $dir/cmdline|" "$dir/loop.sh"
    printf 'printf "%%s %%s %%s\\n" "$XCATMASTER" "$XCATPORT" "$XCATDEST"\n' >>"$dir/loop.sh"
    bash "$dir/loop.sh"
}

@test "an IPv4 master is read as before" {
    run parse_xcatd 'quiet xcatd=192.168.1.1:3001 destiny=install'
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.1 3001 192.168.1.1:3001" ]
}

@test "a bracketed IPv6 master gives the address and the port" {
    run parse_xcatd 'quiet xcatd=[2001:db8:190::1]:3001 destiny=install'
    [ "$status" -eq 0 ]
    [ "$output" = "2001:db8:190::1 3001 [2001:db8:190::1]:3001" ]
}

@test "a bracketed link-local master gives the address and the port" {
    run parse_xcatd 'quiet xcatd=[fe80::1]:3001 destiny=shell'
    [ "$status" -eq 0 ]
    [ "$output" = "fe80::1 3001 [fe80::1]:3001" ]
}

@test "a non-default port is read from the bracketed form" {
    run parse_xcatd 'quiet xcatd=[2001:db8::1]:3002 destiny=install'
    [ "$status" -eq 0 ]
    [ "$output" = "2001:db8::1 3002 [2001:db8::1]:3002" ]
}

@test "the port defaults to 3001 when no xcatd argument is given" {
    run parse_xcatd 'quiet destiny=install'
    [ "$status" -eq 0 ]
    [ "$output" = " 3001 :3001" ]
}

@test "the destination getcert and getdestiny receive is bracketed for IPv6" {
    # doxcat re-joins the pair for /bin/getcert and /bin/getdestiny, which hand it to
    # openssl s_client -connect. Unbracketed, openssl rejects it as ambiguous and the node
    # never obtains a certificate: measured on a node whose cmdline parsed correctly.
    run parse_xcatd 'quiet xcatd=[2001:db8:190::1]:3001 destiny=shell'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[2001:db8:190::1]:3001" ]]
}

@test "the destination is unbracketed for IPv4, so an existing node is unaffected" {
    run parse_xcatd 'quiet xcatd=192.168.1.1:3001 destiny=shell'
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168.1.1:3001" ]]
    [[ "$output" != *"["* ]]
}

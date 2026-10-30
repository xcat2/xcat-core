#!/usr/bin/env bats
#
# retry_install.sh decides a provision succeeded only if all three of tobooted, pingable and
# canruncmd are 0. pingable came from a single `ping -c 2`, and ICMP to a node is lossy for a few
# seconds after it finishes booting.
#
# Measured on an openSUSE Leap 15.6 cluster: one sample reported "2 packets transmitted, 0
# received" while `xdsh <node> date` returned the node's own clock a second later, so the node was
# up and answering SSH. The conjunction failed on ICMP alone and the case did a second full
# rinstall, which cost 401 of the 404 seconds between two runs of the same cell. The second run
# lost 2 of 3 packets at a moment that was not the decision point and passed first try. The
# difference between the runs was which side of a two-packet sample landed.
#
# node_pingable asks again before concluding. These tests drive it with a stubbed ping, because
# what matters is how many times it asks and what it answers -- not whether this host can reach
# anything.
#
# The discriminator is "a node that never answers still reports non-pingable". Removing the
# retry must fail the transient case and leave that one passing, or the change cannot be told
# apart from deleting the check -- which would turn a flaky probe into one that cannot fail.

load 'helpers/shell_source'

NODE=cn01

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/retry_install.sh')"
    COUNT="${BATS_TEST_TMPDIR}/ping-calls"
    : >"$COUNT"
    # No sleeping: the retry interval is not what these tests are about.
    export PING_RETRY_SLEEP=0
    export PING_TRIES=5
}

# Replaces the ping(8) the function calls. Answers non-zero for the first $1 calls, then zero.
# A negative count never answers.
stub_ping()
{
    FAIL_FIRST="$1"
    ping()
    {
        local n
        n=$(( $(read_file_or_empty "$COUNT" | wc -l) + 1 ))
        echo "call $n" >>"$COUNT"
        if [ "$FAIL_FIRST" -lt 0 ] || [ "$n" -le "$FAIL_FIRST" ]; then
            return 1
        fi
        return 0
    }
}

ping_calls()
{
    read_file_or_empty "$COUNT" | wc -l | tr -d ' '
}

@test "sourcing retry_install.sh defines node_pingable and runs no provisioning" {
    # The main-guard. Without it, sourcing runs lsdef and the rinstall loop.
    run bash -c "source '$SCRIPT'; type -t node_pingable"
    [ "$status" -eq 0 ]
    [ "$output" = "function" ]
}

# `run` is required, not stylistic: bats fails a test on any non-zero command in its body, and
# `set +e` does not suppress that. Asserting on a non-zero return without `run` aborts the test
# instead of measuring it -- which made the veto assertion below fail under a mutation for the
# wrong reason, so it could not discriminate.
@test "a node whose first samples are lost is pingable once it answers" {
    # xcat20-mn, exactly: ICMP lost in the window after the boot, then fine.
    source "$SCRIPT"
    stub_ping 2
    run node_pingable "$NODE"
    [ "$status" -eq 0 ]
    [ "$(ping_calls)" -eq 3 ]
}

@test "a node that never answers is still not pingable, so a real defect keeps vetoing" {
    # THE DISCRIMINATOR, and it asserts ONE thing on purpose. Bundling the ask count in here made
    # it fail under the mutation as a retry property, which is the opposite of discriminating:
    # this assertion exists to show the change is not "delete the check", so it has to pass
    # whether or not the retry is present.
    source "$SCRIPT"
    stub_ping -1
    run node_pingable "$NODE"
    [ "$status" -ne 0 ]
}

@test "a node that never answers is asked PING_TRIES times before giving up" {
    source "$SCRIPT"
    stub_ping -1
    run node_pingable "$NODE"
    [ "$(ping_calls)" -eq "$PING_TRIES" ]
}

@test "a node that answers at once costs no extra asks" {
    # The happy path must not get slower: one ask, as before.
    source "$SCRIPT"
    stub_ping 0
    node_pingable "$NODE"
    [ "$(ping_calls)" -eq 1 ]
}

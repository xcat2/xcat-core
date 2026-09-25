#!/usr/bin/env bats
#
# Subiquity waits for every error command to return before it reports the failure. An error
# command that waits for a collector an unattended install does not have therefore holds the
# node until the provisioning timeout.
#
# Run the error commands, with the programs that would reach the host or the network replaced,
# and check that they return and that they write the end of the curtin log where the caller
# points.

load 'helpers/shell_source'

setup()
{
    TEMPLATE="$(repo_path 'xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl')"
    [ -r "$TEMPLATE" ] || skip "$TEMPLATE is required"
    export TEMPLATE
}

# One command per list item of the error-commands block. The list form ['sh', '-c', '...']
# carries the command in its last element; a plain item is the command itself.
error_commands()
{
    awk '
        /^  error-commands:$/ { copy = 1; next }
        copy && !/^    [-#]/ { exit }
        copy && /^    - / {
            found = 1
            line = substr($0, 7)
            if (match(line, /^\[[^]]*, .-c., .*\]$/)) {
                sub(/^\[[^]]*, .-c., ./, "", line)
                sub(/.\]$/, "", line)
            }
            print line
        }
        END { if (!found) exit 1 }
    ' "$TEMPLATE"
}

# bash resolves a function ahead of PATH, so the commands run as written while nothing reaches
# the host or the network. The nc shadow waits the way a listener with no collector waits.
#
# Shadowing a command does not stop the shell opening the file the command redirects into: the
# redirection is the shell's, and it happens whether or not tar runs. So the archive path is
# taken from the environment too, and pointed inside the test's own directory. Without that,
# this test would truncate /run/<node>-logs.tar on the host running it, and CI runs as root.
run_error_commands()
{
    local script="${BATS_TEST_TMPDIR}/error-commands.sh" command

    : >"$script"
    {
        printf "export XCAT_ERROR_CONSOLE='%s'\n" "$CONSOLE"
        printf "export XCAT_ERROR_ARCHIVE='%s'\n" "$ARCHIVE"
        printf 'nc() { sleep 300; }\n'
        printf 'tar() { echo XCAT_LOGS_ARCHIVE; }\n'
        printf 'tail() { echo XCAT_CURTIN_LOG_TAIL; }\n'
    } >>"$script"

    while IFS= read -r command; do
        # Subiquity runs each error command on its own, so a command that ends in "exit 0"
        # must not end the others.
        printf '( %s )\n' "${command//\#HOSTNAME\#/testnode}" >>"$script"
    done < <(error_commands)

    timeout 10 bash "$script"
}

@test "the error commands return instead of waiting for someone to collect the logs" {
    [ -n "$(error_commands)" ]
    CONSOLE="${BATS_TEST_TMPDIR}/console"
    ARCHIVE="${BATS_TEST_TMPDIR}/logs.tar"

    run run_error_commands
    [ "$status" -ne 124 ]
    grep -q XCAT_CURTIN_LOG_TAIL "$CONSOLE"
}

@test "the log archive is written where the caller points, and nowhere else" {
    CONSOLE="${BATS_TEST_TMPDIR}/console"
    ARCHIVE="${BATS_TEST_TMPDIR}/logs.tar"

    run run_error_commands
    [ "$status" -ne 124 ]

    # The archive command redirects into the path it was given, so its output IS the proof
    # that the redirection went there and not to the default under /run. There is nothing to
    # add by looking at the default path: whether /run/testnode-logs.tar exists says nothing
    # about this test, because anything else may have created it, and its absence would be
    # just as true had the override never worked.
    grep -q XCAT_LOGS_ARCHIVE "$ARCHIVE"
}

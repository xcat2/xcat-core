#!/usr/bin/env bats
#
# The Genesis status console is C. setup_file builds its plain-only binary and small test
# programs against state.c, support.c and shell.c with strict warnings. The tests run them
# against a scratch status tree. The Newt interface needs libnewt and is not built here.

load 'helpers/shell_source'

CONSOLE_SRC='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console/src'
STRICT='-D_POSIX_C_SOURCE=200809L -std=c17 -Wall -Wextra -Wpedantic -Werror'

setup_file()
{
    command -v "${CC:-cc}" >/dev/null || skip 'a C compiler is required'
    local src out
    src="$(require_repo_file "$CONSOLE_SRC/console.h")"
    src="${src%/console.h}"
    out="$BATS_FILE_TMPDIR"

    # shellcheck disable=SC2086
    "${CC:-cc}" $STRICT -DXCAT_CONSOLE_PLAIN_ONLY \
        "$src/main.c" "$src/plain_ui.c" "$src/shell.c" "$src/state.c" "$src/support.c" \
        -o "$out/xcat-genesis-console"

    cat >"$out/header-test.c" <<'C'
#include "console.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    for (int index = 1; index < argc; index++)
        printf("%d ", xcat_header_context_columns(atoi(argv[index])));
    printf("\n");
    return 0;
}
C
    # shellcheck disable=SC2086
    "${CC:-cc}" $STRICT -I "$src" "$out/header-test.c" "$src/support.c" -o "$out/header-test"

    # uname is replaced so the architecture comes from XCAT_TEST_ARCH.
    cat >"$out/identity-test.c" <<'C'
#include "console.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>

int xcat_test_uname(struct utsname *name) {
    const char *architecture = getenv("XCAT_TEST_ARCH");

    memset(name, 0, sizeof(*name));
    snprintf(name->machine, sizeof(name->machine), "%s",
             architecture != NULL ? architecture : "x86_64");
    snprintf(name->release, sizeof(name->release), "test-kernel");
    return 0;
}

int main(void) {
    struct console_state state;

    xcat_load_console_state(&state);
    printf("uuid=%s\nfirmware=%s\nboot=%s\n", state.uuid, state.firmware, state.boot_method);
    return 0;
}
C
    # shellcheck disable=SC2086
    "${CC:-cc}" $STRICT -Duname=xcat_test_uname -I "$src" "$out/identity-test.c" \
        "$src/state.c" "$src/support.c" -o "$out/identity-test"

    # Drives the shared status view: its fields, its change detection and the diagnostics.
    cat >"$out/view-test.c" <<'C'
#include "console.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    static char text[8192];
    struct console_state state;
    struct status_view view;
    struct status_view changed;

    xcat_load_console_state(&state);
    xcat_build_status_view(&state, &view);
    if (argc > 1 && strcmp(argv[1], "identity") == 0) {
        printf("%s\n", view.identity);
    } else if (argc > 1 && strcmp(argv[1], "fields") == 0) {
        for (int field = 0; field < STATUS_FIELD_COUNT; field++)
            printf("%d|%s|%s\n", field, view.fields[field].label, view.fields[field].value);
    } else if (argc > 1 && strcmp(argv[1], "changes") == 0) {
        printf("same %d\n", xcat_status_view_changed(&view, &view));
        for (int field = 0; field < STATUS_FIELD_COUNT; field++) {
            changed = view;
            strcat(changed.fields[field].value, "x");
            printf("%d %d\n", field, xcat_status_view_changed(&view, &changed));
        }
    } else {
        xcat_format_diagnostics(&state, text, sizeof(text));
        printf("%s\n", text);
    }
    return 0;
}
C
    # shellcheck disable=SC2086
    "${CC:-cc}" $STRICT -I "$src" "$out/view-test.c" "$src/state.c" "$src/support.c" \
        -o "$out/view-test"

    # execl is replaced: it logs its arguments, then fails like a missing file or runs sh.
    cat >"$out/shell-test.c" <<'C'
#include "console.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int xcat_test_execl(const char *path, const char *arg, ...) {
    const char *mode = getenv("XCAT_TEST_EXEC");
    char *const shell[] = {"sh", "-c", (char *)mode, NULL};
    FILE *log = fopen(getenv("XCAT_TEST_EXEC_LOG"), "w");

    if (log != NULL) {
        fprintf(log, "%s %s\n", path, arg);
        fclose(log);
    }
    if (strcmp(mode, "missing") == 0) {
        errno = ENOENT;
        return -1;
    }
    return execv("/bin/sh", shell);
}

int main(void) {
    printf("%d\n", xcat_run_maintenance_shell());
    return 0;
}
C
    # shellcheck disable=SC2086
    "${CC:-cc}" $STRICT -Dexecl=xcat_test_execl -I "$src" "$out/shell-test.c" \
        "$src/shell.c" "$src/support.c" -o "$out/shell-test"
}

setup()
{
    [ -x "$BATS_FILE_TMPDIR/view-test" ] || skip 'the console test programs were not built'
    CONSOLE="$BATS_FILE_TMPDIR/xcat-genesis-console"
    root="$BATS_TEST_TMPDIR"
    status_dir="$root/status"
    net="$root/sys/class/net/eth0"
    dmi="$root/sys/class/dmi/id"
    mkdir -p "$status_dir" "$net" "$dmi" "$root/proc" "$root/extensions" "$root/providers" \
        "$root/sys/firmware/efi"
    printf 'xcatd=192.0.2.10:3001 BOOTIF=01-52-54-00-00-00-01 gateway=192.0.2.1\n' >"$root/cmdline"
    printf '125.90 200.00\n' >"$root/uptime"
    printf 'NAME="xCAT Genesis"\nVERSION_ID="0.1"\n' >"$root/os-release.real"
    ln -s "$root/os-release.real" "$root/os-release"
    printf '%s\n' SCHEMA=1 STATE=READY 'DETAIL=Management network ready on eth0' \
        STARTED_SECONDS=100 UPDATED_SECONDS=100 VERIFIED_SECONDS=100 >"$status_dir/network.env"
    printf '%s\n' SCHEMA=1 STATE=ACTION_RECEIVED 'DETAIL=Action osimage received' \
        STARTED_SECONDS=110 UPDATED_SECONDS=120 VERIFIED_SECONDS=120 NODE_NAME=compute01 \
        ACTION=osimage TARGET=rocky9 >"$status_dir/registration.env"
    extensions_ready
    ipv4_network_state
    printf 'osimage=rocky9\n' >"$root/destiny"
    printf 'XCAT_NODE_NAME=compute01\n' >"$root/xcat-response.env"
    printf 'up\n' >"$net/operstate"
    printf '52:54:00:00:00:01\n' >"$net/address"
    printf 'TEST-SERIAL-001\n' >"$dmi/product_serial"
    printf '11111111-2222-3333-4444-555555555555\n' >"$dmi/product_uuid"
    : >"$root/extensions/one.raw"
    : >"$root/extensions/two.raw"
    ln -s "$root/extensions/one.raw" "$root/extensions/linked.raw"
    printf '{}\n' >"$root/providers/one.json"
    printf '{}\n' >"$root/providers/two.json"
    ln -s "$root/providers/one.json" "$root/providers/linked.json"

    export XCAT_CMDLINE_FILE="$root/cmdline"
    export XCAT_UPTIME_FILE="$root/uptime"
    export XCAT_OS_RELEASE="$root/os-release"
    export XCAT_STATUS_DIR="$status_dir"
    export XCAT_STATE_FILE="$root/genesis.env"
    export XCAT_DESTINY_FILE="$root/destiny"
    export XCAT_RESPONSE_FILE="$root/xcat-response.env"
    export XCAT_SYS_ROOT="$root/sys"
    export XCAT_PROC_ROOT="$root/proc"
    export XCAT_EXTENSION_DIR="$root/extensions"
    export XCAT_PROVIDER_DIR="$root/providers"
    export XCAT_TEST_ARCH=x86_64
}

extensions_ready()
{
    printf '%s\n' SCHEMA=1 STATE=READY 'DETAIL=Genesis extensions loaded' \
        STARTED_SECONDS=105 UPDATED_SECONDS=106 >"$status_dir/extensions.env"
}

ipv4_network_state()
{
    printf '%s\n' XCATDEST=192.0.2.10:3001 XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=192.0.2.20 \
        XCAT_SOURCE_PREFIXED_ADDRESS=192.0.2.20/24 XCAT_GATEWAY=192.0.2.1 \
        XCAT_DNS_SERVERS=192.0.2.53 "XCAT_NETWORK_METHOD=${1:-auto}" XCAT_LINK_STATE=up \
        XCAT_MAC_ADDRESS=52:54:00:00:00:01 >"$root/genesis.env"
}

console_once()
{
    run "$CONSOLE" --once
}

# $output holds these lines in this order, one after the other.
has_lines()
{
    local expected
    expected="$(printf '%s\n' "$@")"
    [[ "$output" == *"$expected"* ]] || { printf 'missing:\n%s\n' "$expected" >&2; return 1; }
}

has_no_match()
{
    ! grep -Eq -- "$1" <<<"$output"
}

@test "narrow terminals leave no writable header context" {
    run "$BATS_FILE_TMPDIR/header-test" 0 19 20 21 80
    [ "$output" = '0 0 0 1 60 ' ]
}

@test "the plain console renders a status snapshot with explicit, separate fields" {
    console_once
    [ "$status" -eq 0 ]
    has_lines 'xCAT Genesis | ACTION_RECEIVED | in stage 00:00:15'
    has_lines 'node: compute01' 'serial: TEST-SERIAL-001'
    has_lines 'interface: eth0' 'link: up' 'method: DHCP' 'address: 192.0.2.20/24' 'MAC: 52:54:00:00:00:01'
    has_lines 'xCAT server: 192.0.2.10:3001' 'xCAT contact: Action received'
    has_lines 'action: Boot assigned image' 'target: rocky9' 'progress: none'
    has_no_match '[Ll]ast contact'
    has_no_match 'extensions:|providers:|Linux '
    has_no_match $'\e'
}

@test "the console reads IBM Z identity and reports only a marked boot path" {
    rm "$dmi/product_serial" "$dmi/product_uuid"
    printf '%s\n' 'Plant:                02' 'Sequence Code:        0000000012345' \
        'LPAR UUID:            93724168-fda3-429b-8b28-a5d245dcb3ff' \
        'VM00 UUID:            82038f2a-1344-aaf7-1a85-2a7250be2076' >"$root/proc/sysinfo"
    printf 'xcatd=192.0.2.10:3001\n' >"$root/cmdline"
    export XCAT_TEST_ARCH=s390x
    run "$BATS_FILE_TMPDIR/identity-test"
    [ "$status" -eq 0 ]
    [ "$output" = 'uuid=82038f2a-1344-aaf7-1a85-2a7250be2076
firmware=not reported
boot=not reported' ]
    printf 'xcatd=192.0.2.10:3001 xcat.bootloader=s390-ccw\n' >"$root/cmdline"
    run "$BATS_FILE_TMPDIR/identity-test"
    [ "$output" = 'uuid=82038f2a-1344-aaf7-1a85-2a7250be2076
firmware=s390-ccw BIOS
boot=QEMU TFTP loader' ]
}

@test "the console uses the LPAR UUID only when the LPAR is the guest" {
    rm "$dmi/product_serial" "$dmi/product_uuid"
    export XCAT_TEST_ARCH=s390x
    printf 'LPAR UUID:            93724168-fda3-429b-8b28-a5d245dcb3ff\n' >"$root/proc/sysinfo"
    run "$BATS_FILE_TMPDIR/identity-test"
    has_lines 'uuid=93724168-fda3-429b-8b28-a5d245dcb3ff'
    printf '%s\n' 'VM00 Control Program: z/VM 7.3.0' \
        'LPAR UUID:            93724168-fda3-429b-8b28-a5d245dcb3ff' >"$root/proc/sysinfo"
    run "$BATS_FILE_TMPDIR/identity-test"
    has_lines 'uuid=not reported'
}

@test "the console reads xCAT parameters after byte 512 of the command line" {
    grep -v '^XCATDEST=' "$root/genesis.env" >"$root/genesis.env.new"
    mv "$root/genesis.env.new" "$root/genesis.env"
    { for _ in $(seq 100); do printf 'quiet '; done
      printf 'xcatd=198.51.100.10:3001 BOOTIF=01-52-54-00-00-00-01\n'; } >"$root/cmdline"
    console_once
    has_lines 'xCAT server: 198.51.100.10:3001'
}

@test "an extension verification failure stops the main status with a recovery hint" {
    printf '%s\n' SCHEMA=1 STATE=FAILED 'DETAIL=extension signature verification failed' \
        STARTED_SECONDS=123 UPDATED_SECONDS=124 CODE=EXTENSION_VERIFICATION_FAILED \
        'RECOVERY=Check extension images, manifests, signatures, and trusted keys' \
        >"$status_dir/extensions.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'error: EXTENSION_VERIFICATION_FAILED: extension signature verification failed'
    has_lines 'recovery: Check extension images, manifests, signatures, and trusted keys'
}

@test "automatic IPv6 and manual network setup have accurate method labels" {
    printf '%s\n' 'XCATDEST=[2001:db8::10]:3001' XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=2001:db8::20 \
        XCAT_SOURCE_PREFIXED_ADDRESS=2001:db8::20/64 XCAT_GATEWAY=2001:db8::1 \
        XCAT_DNS_SERVERS=2001:db8::53 XCAT_NETWORK_METHOD=auto XCAT_LINK_STATE=up \
        XCAT_MAC_ADDRESS=52:54:00:00:00:01 >"$root/genesis.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'method: SLAAC/DHCPv6' 'address: 2001:db8::20/64'
    ipv4_network_state manual
    console_once
    [ "$status" -eq 0 ]
    has_lines 'method: Static'
}

@test "action execution becomes the overall state and overrides the registration snapshot" {
    printf '%s\n' SCHEMA=1 STATE=RUNNING 'DETAIL=Rebooting into the assigned image' \
        STARTED_SECONDS=122 UPDATED_SECONDS=124 VERIFIED_SECONDS=124 ACTION=install \
        'TARGET=rocky9 install image' >"$status_dir/action.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'xCAT Genesis | RUNNING | in stage 00:00:03'
    has_lines 'action: Install assigned image' 'target: rocky9 install image' 'progress: none'
}

@test "an action failure stays on the main page with the same detail rows" {
    printf '%s\n' SCHEMA=1 STATE=FAILED 'DETAIL=Unsigned runimage actions are not supported' \
        STARTED_SECONDS=124 UPDATED_SECONDS=124 CODE=UNSAFE_LEGACY_ACTION \
        'RECOVERY=Package the operation as a signed Genesis system extension' \
        ACTION=runimage TARGET=legacy.tgz >"$status_dir/action.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'error: UNSAFE_LEGACY_ACTION: Unsigned runimage actions are not supported'
    has_no_match '^(target|progress):'
}

@test "a failed component becomes the overall state with an exact error and a recovery hint" {
    printf '%s\n' SCHEMA=1 STATE=FAILED 'DETAIL=No valid response from xCAT' \
        STARTED_SECONDS=120 UPDATED_SECONDS=124 CODE=XCAT_RESPONSE_UNAVAILABLE \
        'RECOVERY=Check xcatd and the management network' >"$status_dir/registration.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'xCAT Genesis | FAILED | in stage 00:00:05'
    has_lines 'error: XCAT_RESPONSE_UNAVAILABLE: No valid response from xCAT'
    has_lines 'xCAT contact: Failed: No valid response from xCAT'
    has_lines 'recovery: Check xcatd and the management network'
}

@test "the retry countdown uses the structured status fields" {
    printf '%s\n' SCHEMA=1 STATE=CONTACTING_XCAT 'DETAIL=xCAT has not answered yet' \
        STARTED_SECONDS=120 UPDATED_SECONDS=124 ATTEMPT=2 ATTEMPT_LIMIT=6 NEXT_RETRY_SECONDS=5 \
        >"$status_dir/registration.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'action: Boot assigned image' 'target: rocky9' 'progress: Attempt 2 of 6; retry in 4s'
}

@test "an empty node response is shown as unassigned" {
    # A registration record without NODE_NAME, so the response file decides.
    printf '%s\n' SCHEMA=1 STATE=CONTACTING_XCAT 'DETAIL=xCAT has not answered yet' \
        STARTED_SECONDS=120 UPDATED_SECONDS=124 >"$status_dir/registration.env"
    printf 'XCAT_NODE_NAME=\n' >"$root/xcat-response.env"
    console_once
    [ "$status" -eq 0 ]
    has_lines 'node: unassigned'
}

@test "the shared status view defines every main-page field" {
    run "$BATS_FILE_TMPDIR/view-test" fields
    [ "$status" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq 15 ]
    [ -z "$(awk -F'|' '$2 == ""' <<<"$output")" ]
}

@test "plain output prints the shared status view, in order" {
    run "$BATS_FILE_TMPDIR/view-test" fields
    view="$(cut -d'|' -f3- <<<"$output")"
    console_once
    plain="$(sed -n 's/^xCAT Genesis | \(.*\) | in stage \(.*\)$/\1\n\2/p; /^[A-Za-z][A-Za-z ]*: /s/^[^:]*: //p' <<<"$output")"
    [ "$plain" = "$view" ]
}

@test "the header identity is the node and serial, or the local hostname before assignment" {
    run "$BATS_FILE_TMPDIR/view-test" identity
    [ "$output" = 'compute01 | TEST-SERIAL-001' ]
    printf '%s\n' SCHEMA=1 STATE=CONTACTING_XCAT 'DETAIL=xCAT has not answered yet' \
        STARTED_SECONDS=120 UPDATED_SECONDS=124 >"$status_dir/registration.env"
    printf 'XCAT_NODE_NAME=\n' >"$root/xcat-response.env"
    run "$BATS_FILE_TMPDIR/view-test" identity
    [ "$output" = "$(hostname) | TEST-SERIAL-001" ]
    [[ "$output" != *x86_64* ]]
}

@test "every shared field but the stage timer takes part in change detection" {
    run "$BATS_FILE_TMPDIR/view-test" changes
    [ "$status" -eq 0 ]
    has_lines 'same 0'
    [ "$(grep -c ' 1$' <<<"$output")" -eq 14 ]
    has_lines '1 0'
}

@test "diagnostics separate each section with an empty line and omit component timers" {
    run "$BATS_FILE_TMPDIR/view-test" diagnostics
    [ "$status" -eq 0 ]
    for section in 'Identity' 'System' 'Management network' 'xCAT' 'Action' 'Runtime'; do
        grep -A1 -x "$section" <<<"$output" | tail -n1 | grep -qx ''
    done
    for section in 'System' 'Management network' 'xCAT' 'Action' 'Runtime'; do
        grep -B1 -x "$section" <<<"$output" | head -n1 | grep -qx ''
    done
    has_no_match 'Last contact|Uptime'
}

@test "the maintenance shell runs the packaged executable and reports a launch failure" {
    export XCAT_TEST_EXEC_LOG="$root/exec.log"
    XCAT_TEST_EXEC=missing run "$BATS_FILE_TMPDIR/shell-test"
    [ "$output" = "$(printf '%d' 2)" ]
    [ "$(cat "$XCAT_TEST_EXEC_LOG")" = '/usr/libexec/xcat/genesis-maintenance-shell genesis-maintenance-shell' ]
}

@test "the maintenance shell accepts any exit status of the shell it started" {
    export XCAT_TEST_EXEC_LOG="$root/exec.log"
    XCAT_TEST_EXEC='exit 3' run "$BATS_FILE_TMPDIR/shell-test"
    [ "$output" = 0 ]
}

# Run the plain console on a terminal with this input, for 4 s.
plain_on_terminal()
{
    command -v script >/dev/null || skip 'script is required'
    run bash -c 'printf "%b" "$1" | timeout 4 script -qec "$2 --plain" /dev/null' \
        plain "$1" "$CONSOLE"
}

@test "plain mode advertises and accepts the shell command, and confirms root access" {
    plain_on_terminal 'shell\nn\n'
    has_lines 'Type shell and press Enter for maintenance.'
    [[ "$output" == *'Open a root maintenance shell? [y/N]'* ]]
    [[ "$output" == *'Maintenance shell cancelled.'* ]]
}

@test "plain mode opens the shell through the common launcher" {
    [ ! -e /usr/libexec/xcat/genesis-maintenance-shell ] || skip 'the host has a maintenance shell'
    plain_on_terminal 'shell\ny\n'
    [[ "$output" == *'Maintenance shell could not be opened: No such file or directory'* ]]
    [[ "$output" == *'Returned to the Genesis status console.'* ]]
}

@test "diagnostics recognize the xNBA and PXELINUX markers, with an honest PXE fallback" {
    for pair in xnba:xNBA pxelinux:PXELINUX; do
        printf 'xcatd=192.0.2.10:3001 BOOTIF=01-52-54-00-00-00-01 xcat.bootloader=%s\n' \
            "${pair%%:*}" >"$root/cmdline"
        run "$BATS_FILE_TMPDIR/identity-test"
        has_lines "boot=${pair#*:}"
    done
    printf 'xcatd=192.0.2.10:3001 BOOTIF=01-52-54-00-00-00-01\n' >"$root/cmdline"
    run "$BATS_FILE_TMPDIR/identity-test"
    has_lines 'boot=PXE (unknown loader)'
}

@test "the stage duration is labelled In stage" {
    run "$BATS_FILE_TMPDIR/view-test" fields
    has_lines '1|In stage|00:00:15'
}

#!/usr/bin/env bats
#
# Run each postinstall script that disables SELinux over a scratch image root, and read the
# config it writes. genimage gives the image root as $1, so every write stays under it.

load 'helpers/shell_source'

setup()
{
    IMAGE_ROOT="${BATS_TEST_TMPDIR}/rootimg"
    CONFIG="${IMAGE_ROOT}/etc/selinux/config"
    mkdir -p "${IMAGE_ROOT}/etc/selinux" "${IMAGE_ROOT}/tmp"
}

# Each postinstall script that writes the SELinux config. A symlink shares the file it points
# at, so -type f gives one entry for each distinct script.
selinux_postinstalls()
{
    find "$(repo_root)" -name .git -prune -o -name '*.postinstall' -type f -print |
        xargs -r grep -l 'etc/selinux/config' | sort
}

# The stock EL config. The third comment line holds the word permissive, which an unanchored
# pattern matches.
write_config()
{
    cat >"$CONFIG" <<END
# SELINUX= can take one of these three values:
#     enforcing - SELinux security policy is enforced.
#     permissive - SELinux prints warnings instead of enforcing.
#     disabled - No SELinux policy is loaded.
SELINUX=$1
SELINUXTYPE=targeted
END
}

# The arguments genimage gives a postinstall script. GITREPO is read by the xcat_inventory
# fixture, which calls a second script beside its own directory.
run_postinstall()
{
    local script="$1"
    GITREPO="$(dirname "$(dirname "$script")")" \
        bash "$script" "$IMAGE_ROOT" 10 x86_64 compute "${BATS_TEST_TMPDIR}/workdir" 2>&1
}

complain()
{
    printf '%s: %s\n' "$1" "$2" >&2
    return 1
}

@test "every postinstall that writes the SELinux config is under test" {
    run selinux_postinstalls
    [ "$status" -eq 0 ]
    [[ "$output" == *"xCAT-server/share/xcat/netboot/rh/compute.rhels10.x86_64.postinstall"* ]]
    [[ "$output" == *"xCAT-server/share/xcat/netboot/rh/service.postinstall"* ]]
    [[ "$output" == *"xCAT-server/share/xcat/netboot/rocky/compute.rocky10.riscv64.postinstall"* ]]
    [ "$(printf '%s\n' "$output" | wc -l)" -ge 13 ]
}

@test "an enforcing config becomes SELINUX=disabled" {
    for script in $(selinux_postinstalls); do
        write_config enforcing
        run run_postinstall "$script"
        [ "$status" -eq 0 ] || complain "$script" "exit $status: $output"
        grep -qx 'SELINUX=disabled' "$CONFIG" ||
            complain "$script" "no SELINUX=disabled line: $(grep '^SELINUX=' "$CONFIG")"
    done
}

@test "a permissive config becomes SELINUX=disabled and not SELINUX=SELINUX=disabled" {
    for script in $(selinux_postinstalls); do
        write_config permissive
        run run_postinstall "$script"
        [ "$status" -eq 0 ] || complain "$script" "exit $status: $output"
        grep -qx 'SELINUX=disabled' "$CONFIG" ||
            complain "$script" "no SELINUX=disabled line: $(grep '^SELINUX=' "$CONFIG")"
        refute_grep -q 'SELINUX=SELINUX=' "$CONFIG" ||
            complain "$script" "the key is doubled: $(grep 'SELINUX=SELINUX=' "$CONFIG")"
    done
}

@test "a config that is already disabled keeps every line" {
    for script in $(selinux_postinstalls); do
        write_config disabled
        cp "$CONFIG" "${BATS_TEST_TMPDIR}/before"
        run run_postinstall "$script"
        [ "$status" -eq 0 ] || complain "$script" "exit $status: $output"
        diff -u "${BATS_TEST_TMPDIR}/before" "$CONFIG" ||
            complain "$script" "the disabled config changed"
    done
}

@test "the comment that names permissive keeps its text" {
    local comment='#     permissive - SELinux prints warnings instead of enforcing.'
    for script in $(selinux_postinstalls); do
        write_config enforcing
        run run_postinstall "$script"
        [ "$status" -eq 0 ] || complain "$script" "exit $status: $output"
        grep -qxF "$comment" "$CONFIG" ||
            complain "$script" "the comment changed: $(grep -n permissive "$CONFIG")"
    done
}

@test "an absent SELinux config does not fail the script" {
    for script in $(selinux_postinstalls); do
        rm -f "$CONFIG"
        run run_postinstall "$script"
        [ "$status" -eq 0 ] || complain "$script" "exit $status: $output"
        [ ! -e "$CONFIG" ] || complain "$script" "created $CONFIG"
        # sed names the file it cannot read, so this text appears only when the script runs
        # the substitution on an image that has no SELinux config.
        [[ "$output" != *"selinux/config"* ]] ||
            complain "$script" "read a config that is not there: $output"
    done
}

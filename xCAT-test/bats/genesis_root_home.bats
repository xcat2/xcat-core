#!/usr/bin/env bats
#
# Drive the /etc/passwd rewrite out of the Genesis dracut cmdline hooks.
#
# mknb writes the management node key to /.ssh/authorized_keys for the legacy Genesis
# image, so sshd finds it only while the home directory of root is /. The hook makes it /
# by deleting the root entry the image ships and appending its own. Run that rewrite
# against every root entry shape dracut writes and read back the result.

load 'helpers/shell_source'

# dracut 99base writes the root entry itself. Up to dracut 057 the password field is always
# x; from dracut 060 the x arrives only with --hostonly, and the Genesis image is built -N.
DRACUT_049_057='root:x:0:0::/root:/bin/sh'
DRACUT_107='root::0:0::/root:/bin/sh'

# A user name that starts with root but is not root. The delete must keep this line.
DECOY='rootfsadm:x:501:501::/home/rootfsadm:/sbin/nologin'

# Lift the /etc/passwd rewrite out of a hook that cannot be sourced: the hook mounts
# filesystems, starts udev and ends in an endless loop.
extract_passwd_block()
{
    local hook="$1"
    awk '
        /^sed .*\/etc\/passwd$/ { copy = 1 }
        copy { print }
        copy && /^__ENDL$/ { found = 1; exit }
        END { if (!found) exit 1 }
    ' "$hook"
}

# Run the extracted block against a scratch passwd file and print the result. The block names
# /etc/passwd literally, so the path is redirected into the scratch tree first, and the run is
# refused if any reference to the real file survives: CI runs this as root.
run_rewrite()
{
    local hook="$1" shipped="$2"
    local dir="${BATS_TEST_TMPDIR}/rewrite"
    local passwd="$dir/passwd" block script

    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%s\n%s\n' "$shipped" "$DECOY" >"$passwd"

    block="$(extract_passwd_block "$(repo_path "$hook")")" ||
        { echo "$hook: the /etc/passwd rewrite was not found" >&2; return 99; }

    [ "$(grep -o -F '/etc/passwd' <<<"$block" | wc -l)" -eq 2 ] ||
        { echo "$hook: expected 2 references to /etc/passwd" >&2; return 98; }
    script="${block//\/etc\/passwd/$passwd}"
    case "$script" in
    */etc/passwd*) echo "$hook: a reference to the real /etc/passwd survived" >&2; return 97 ;;
    esac

    bash -c "set -e
$script" || return 1
    cat "$passwd"
}

assert_root_home_is_slash()
{
    local hook="$1" shipped="$2" passwd
    passwd="$(run_rewrite "$hook" "$shipped")"

    [ "$(grep -c '^root:' <<<"$passwd")" -eq 1 ]
    [ "$(grep '^root:' <<<"$passwd")" = 'root:x:0:0::/:/bin/bash' ]
    grep -qxF "$DECOY" <<<"$passwd"
}

assert_hook()
{
    local hook="$1"
    [ -r "$(repo_path "$hook")" ] || skip "$hook is required"
    assert_root_home_is_slash "$hook" "$DRACUT_049_057"
    assert_root_home_is_slash "$hook" "$DRACUT_107"
}

@test "the legacy hook gives root the home directory /" {
    assert_hook 'xCAT-genesis-builder/xcat-cmdline.sh'
}

@test "the el dracut 105 hook gives root the home directory /" {
    assert_hook 'xCAT-genesis-builder/dracut_105/el/xcat-cmdline.sh'
}

@test "the ubuntu dracut 105 hook gives root the home directory /" {
    assert_hook 'xCAT-genesis-builder/dracut_105/ubuntu/xcat-cmdline.sh'
}

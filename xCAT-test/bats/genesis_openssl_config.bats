#!/usr/bin/env bats
#
# The Genesis payload must carry the openssl config file. openssl req reads
# OPENSSLDIR/openssl.cnf and exits 1 when it is absent, so getcert makes no certificate
# request and the node never reports a destiny.

load 'helpers/shell_source'

setup()
{
    HOST_CNF="$(openssl version -d 2>/dev/null | sed -e 's/^OPENSSLDIR: *"*//' -e 's/"*$//')/openssl.cnf"
    [ -e "$HOST_CNF" ] || skip "this host has no $HOST_CNF to install"
    export HOST_CNF
}

# Run the module's install() with every dracut helper replaced by a recorder, so the test reads
# what the module asks the payload to carry rather than matching the module's source.
record_install()
{
    local module="$1" log="$2"
    : >"$log"
    (
        for helper in dracut_install inst inst_simple inst_multiple inst_binary inst_script \
                      inst_symlink inst_dir inst_hook inst_rules instmods; do
            eval "$helper() { printf '%s\n' \"\$@\" >>'$log'; return 0; }"
        done
        # Anything the module calls that this host lacks must not stop install().
        command_not_found_handle() { return 0; }
        dfatal() { printf 'dfatal %s\n' "$*" >>"$log"; }
        moddir="${BATS_TEST_TMPDIR}"; hostonly=''; dracutsysrootdir=''; srcmods=''
        . "$module" >/dev/null 2>&1 || true
        install >/dev/null 2>&1 || true
    )
}

@test "the ubuntu module installs the openssl config its own openssl names" {
    module="$(repo_path 'xCAT-genesis-base/dracut_105/ubuntu/module-setup.sh')"
    [ -r "$module" ] || skip "$module is required"
    record_install "$module" "${BATS_TEST_TMPDIR}/ubuntu.log"
    [ -s "${BATS_TEST_TMPDIR}/ubuntu.log" ]
    grep -q "$HOST_CNF" "${BATS_TEST_TMPDIR}/ubuntu.log"
}

@test "the el module installs the openssl config its own openssl names" {
    module="$(repo_path 'xCAT-genesis-base/dracut_105/el/module-setup.sh')"
    [ -r "$module" ] || skip "$module is required"
    record_install "$module" "${BATS_TEST_TMPDIR}/el.log"
    [ -s "${BATS_TEST_TMPDIR}/el.log" ]
    grep -q "$HOST_CNF" "${BATS_TEST_TMPDIR}/el.log"
}

@test "openssl itself is still installed, so the config is an addition" {
    module="$(repo_path 'xCAT-genesis-base/dracut_105/ubuntu/module-setup.sh')"
    [ -r "$module" ] || skip "$module is required"
    record_install "$module" "${BATS_TEST_TMPDIR}/u2.log"
    grep -qx 'openssl' "${BATS_TEST_TMPDIR}/u2.log"
}

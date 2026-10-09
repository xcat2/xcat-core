#!/usr/bin/env bats
# enable_crb.sh enables CodeReady Builder through RHSM on RHEL and through dnf elsewhere.

load 'helpers/shell_source'

setup()
{
    source "$(require_repo_file 'xCAT-test/autotest/testcase/go_xcat/enable_crb.sh')"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    : >"$CALLS"
    EL_MAJOR=9
    RHSM_REPOS=''
    DNF_ENABLES='crb powertools'
    SM_ENABLE_RC=0

    rpm() { [ "$*" = '-E %rhel' ] && echo "$EL_MAJOR"; }
    uname() { echo x86_64; }
    subscription-manager()
    {
        echo "subscription-manager $*" >>"$CALLS"
        case "$*" in
            'repos --list') printf 'Repo ID:   %s\n' $RHSM_REPOS ;;
            'repos --enable '*) return "$SM_ENABLE_RC" ;;
        esac
    }
    dnf()
    {
        echo "dnf $*" >>"$CALLS"
        [ "$1 $2" = 'config-manager --set-enabled' ] || return 1
        case " $DNF_ENABLES " in *" $3 "*) return 0 ;; esac
        return 1
    }
}

@test "an RHSM-managed RHEL node enables the codeready-builder repository through subscription-manager" {
    RHSM_REPOS='rhel-9-for-x86_64-baseos-rpms codeready-builder-for-rhel-9-x86_64-rpms'
    DNF_ENABLES=''
    run enable_crb
    [ "$status" -eq 0 ]
    grep -qx 'subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms' "$CALLS"
    refute_grep -q '^dnf ' "$CALLS"
}

@test "a failed subscription-manager enable fails enable_crb" {
    RHSM_REPOS='codeready-builder-for-rhel-9-x86_64-rpms'
    SM_ENABLE_RC=1
    run enable_crb
    [ "$status" -ne 0 ]
}

@test "an EL9 node without RHSM enables crb through dnf" {
    run enable_crb
    [ "$status" -eq 0 ]
    grep -qx 'dnf config-manager --set-enabled crb' "$CALLS"
    refute_grep -q 'repos --enable' "$CALLS"
}

@test "an EL8 node without RHSM enables powertools through dnf" {
    EL_MAJOR=8
    DNF_ENABLES='powertools'
    run enable_crb
    [ "$status" -eq 0 ]
    grep -qx 'dnf config-manager --set-enabled powertools' "$CALLS"
}

@test "an EL9 node where dnf cannot enable crb fails enable_crb" {
    DNF_ENABLES=''
    run enable_crb
    [ "$status" -ne 0 ]
}

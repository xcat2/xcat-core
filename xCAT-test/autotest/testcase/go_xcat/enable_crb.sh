#!/bin/bash
# Enable the CodeReady Builder repository that go-xcat needs on an EL node.
# Run it on the node with xdsh -e. A bats test sources it and calls enable_crb.

enable_crb()
{
    local major arch rhsm_repo dnf_repo

    major=$(rpm -E %rhel)
    arch=$(uname -m)

    # On RHEL, RHSM owns the repository and dnf config-manager cannot enable it.
    rhsm_repo="codeready-builder-for-rhel-${major}-${arch}-rpms"
    if subscription-manager repos --list 2>/dev/null |
        grep -Eq "^Repo ID:[[:space:]]+${rhsm_repo}[[:space:]]*\$"; then
        subscription-manager repos --enable "$rhsm_repo"
        return
    fi

    dnf_repo=crb
    [ "$major" = 8 ] && dnf_repo=powertools
    dnf config-manager --set-enabled "$dnf_repo" ||
        dnf config-manager setopt "${dnf_repo}.enabled=1"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    enable_crb
fi

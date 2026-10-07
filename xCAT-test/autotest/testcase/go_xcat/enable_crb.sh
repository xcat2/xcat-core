#!/bin/bash
# Enable the CodeReady Builder repository that go-xcat needs on an EL node.
# Run it on the node with xdsh -e. A bats test sources it and calls enable_crb.

enable_crb()
{
    dnf config-manager --set-enabled crb ||
        dnf config-manager --set-enabled powertools ||
        dnf config-manager setopt crb.enabled=1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    enable_crb
fi

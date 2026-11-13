#!/usr/bin/env bats
#
# The netplan the Subiquity late-command writes into the installed system.
#
# The template renders #SUBIQUITYTARGETDHCP# into a printf argument list, so the shell decides
# which lines reach /etc/netplan/00-xcat-install.yaml and in which order. An IPv6-only node now
# gets static keys there: systemd-networkd generates its own DUID, so a node that asked for
# DHCPv6 after reboot took an address out of the dynamic range, which has no PTR record, and
# xcatd could not tell which node ran xcatdsklspost.
#
# Perl renders the arguments, the shell writes the file, so this half is a bats test.

load 'helpers/shell_source'

MAC='aa:bb:cc:dd:ee:07'
DHCP4_KEYS='"      dhcp4: true" "      dhcp4-overrides:" "        use-domains: true"'
STATIC6_KEYS='"      dhcp4: false" "      addresses: [2001:db8:147::20/64]" "      routes:" "        - to: default" "          via: 2001:db8:147::1" "      nameservers:" "        addresses: [2001:db8:147::1]"'

setup()
{
    TMPL="$(require_repo_file \
      'xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl')"
    SNIPPET="$(extract_line_range "$TMPL" \
      'installnic="#SUBIQUITYINSTALLNIC#"' 'chmod 600 /target/etc/netplan')" \
      || skip 'the netplan late-command is not in the template'
    # The autoinstall carries the late-command as a single-quoted YAML scalar, so each quote in
    # the shell is doubled. Undo that, and keep the writes inside the test tree.
    SNIPPET="${SNIPPET//\'\'/\'}"
    SNIPPET="${SNIPPET//\/target\//${BATS_TEST_TMPDIR}/target/}"
    NETPLAN="${BATS_TEST_TMPDIR}/target/etc/netplan/00-xcat-install.yaml"
}

render()
{
    local script="$SNIPPET"
    script="${script//'#SUBIQUITYINSTALLNIC#'/$1}"
    script="${script//'#SUBIQUITYINSTALLMAC#'/$2}"
    script="${script//'#SUBIQUITYTARGETDHCP#'/$3}"
    sh -c "set -e
$script"
}

@test "an IPv4 node is written the DHCPv4 netplan it always had" {
    render 'eno1' "$MAC" "$DHCP4_KEYS"
    [ "$(cat "$NETPLAN")" = 'network:
  version: 2
  ethernets:
    xcat-install:
      match:
        macaddress: "aa:bb:cc:dd:ee:07"
      set-name: eno1
      dhcp4: true
      dhcp4-overrides:
        use-domains: true' ]
}

@test "an IPv6-only node is written its reserved address" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    [ "$(cat "$NETPLAN")" = 'network:
  version: 2
  ethernets:
    xcat-install:
      match:
        macaddress: "aa:bb:cc:dd:ee:07"
      set-name: eno1
      dhcp4: false
      addresses: [2001:db8:147::20/64]
      routes:
        - to: default
          via: 2001:db8:147::1
      nameservers:
        addresses: [2001:db8:147::1]' ]
}

@test "the static address survives the printf argument list" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    grep -qx '      addresses: \[2001:db8:147::20/64\]' "$NETPLAN"
}

@test "the default route is written as its own netplan list item" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    grep -qx '        - to: default' "$NETPLAN"
    grep -qx '          via: 2001:db8:147::1' "$NETPLAN"
}

@test "the static keys are never mixed with a DHCP request" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    # grep answers 2 for a file that is not there, and refute_grep reads that as "absent", so
    # the two refutals below need a line that must be present to prove the file was written.
    grep -qx '      dhcp4: false' "$NETPLAN"
    refute_grep -q 'dhcp6' "$NETPLAN"
    refute_grep -q 'dhcp4: true' "$NETPLAN"
}

@test "a node with no interface name to set still gets the static address" {
    render '' "$MAC" "$STATIC6_KEYS"
    refute_grep -q 'set-name' "$NETPLAN"
    grep -qx '      addresses: \[2001:db8:147::20/64\]' "$NETPLAN"
}

@test "the netplan binds to the MAC of the node, whichever branch wrote it" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    grep -qx "        macaddress: \"$MAC\"" "$NETPLAN"
    render '' "$MAC" "$STATIC6_KEYS"
    grep -qx "        macaddress: \"$MAC\"" "$NETPLAN"
}

@test "netplan refuses a file other users can read, so the late-command chmods it" {
    render 'eno1' "$MAC" "$STATIC6_KEYS"
    [ "$(stat -c '%a' "$NETPLAN")" = '600' ]
}

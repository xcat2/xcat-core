#!/bin/sh

xcat_network_plan()
(
    xcat_net_encoded=$1
    xcat_net_mac=$2
    xcat_net_output=$3
    [ -n "$xcat_net_encoded" ] && [ "${#xcat_net_encoded}" -le 8192 ] || exit 1
    case "$xcat_net_encoded" in *[!A-Za-z0-9+/=]*) exit 1 ;; esac
    printf '%s' "$xcat_net_encoded" | base64 -d > "$xcat_net_output.input" || exit 1
    [ "$(base64 < "$xcat_net_output.input" | tr -d '\n')" = "$xcat_net_encoded" ] || exit 1
    LC_ALL=C awk '/[^ -~]/ {exit 1}' "$xcat_net_output.input" || exit 1
    unset NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS
    xcat_net_count=0
    xcat_net_bytes=0
    while IFS= read -r xcat_net_line; do
        xcat_net_count=$((xcat_net_count + 1))
        xcat_net_bytes=$((xcat_net_bytes + ${#xcat_net_line} + 1))
        xcat_net_key=${xcat_net_line%%=*}
        xcat_net_value=${xcat_net_line#*=}
        case "$xcat_net_count:$xcat_net_key" in
            1:interface) xcat_net_interface=$xcat_net_value ;;
            2:mac) [ "$xcat_net_value" = "$xcat_net_mac" ] || exit 1 ;;
            3:mtu) xcat_net_mtu=$xcat_net_value ;;
            4:NICTYPES|5:NICDEVICES|6:NICEXTRAPARAMS|7:NICMACS) export "$xcat_net_key=$xcat_net_value" ;;
            *) exit 1 ;;
        esac
    done < "$xcat_net_output.input"
    [ "$xcat_net_count" = 7 ] && [ "$(wc -c < "$xcat_net_output.input")" -eq "$xcat_net_bytes" ] || exit 1
    awk -v mode=bootstrap -v bootstrapnic="$xcat_net_interface" -v bootmac="$xcat_net_mac" -v bootstrap_mtu="$xcat_net_mtu" \
        -f /usr/local/libexec/confignetwork-freebsd.awk > "$xcat_net_output"
)

xcat_network_bootstrap()
{
    XCAT_BOOT_NETWORK_BASE64=
    xcat_net_chunks=$(kenv -q xcat_network_chunks || :)
    [ -n "$xcat_net_chunks" ] || return 0
    case "$xcat_net_chunks" in [1-9]|[1-6][0-9]) ;; *) return 1 ;; esac
    xcat_net_index=0
    while [ "$xcat_net_index" -lt "$xcat_net_chunks" ]; do
        xcat_net_chunk=$(kenv -q "xcat_network_$xcat_net_index") || return 1
        [ -n "$xcat_net_chunk" ] && [ "${#xcat_net_chunk}" -le 120 ] || return 1
        XCAT_BOOT_NETWORK_BASE64=$XCAT_BOOT_NETWORK_BASE64$xcat_net_chunk
        xcat_net_index=$((xcat_net_index + 1))
    done
    XCAT_BOOT_NETWORK_PLAN=$XCAT_WORK/bootstrap.plan
    xcat_network_plan "$XCAT_BOOT_NETWORK_BASE64" "$XCAT_BOOT_MAC" "$XCAT_BOOT_NETWORK_PLAN" || return 1
    # Check every physical identity and clone name before changing interfaces.
    while IFS="$(printf '\t')" read -r kind nic value; do
        case "$kind" in
            M)
                [ "$(ifconfig "$nic" | awk '$1=="ether" {print tolower($2)}')" = "$value" ] || return 1
                ifconfig "$nic" | awk '$1=="inet" {exit 1}' || return 1 ;;
            I)
                [ "$value" = ethernet ] || ! ifconfig "$nic" >/dev/null 2>&1 || return 1 ;;
        esac
    done < "$XCAT_BOOT_NETWORK_PLAN"
    for module in if_infiniband if_lagg bridgestp if_bridge if_vlan; do
        kldload -n "$module" || return 1
    done
    while IFS="$(printf '\t')" read -r kind nic value; do
        case "$kind" in
            B) XCAT_PROVISIONING_IF=$nic ;;
            I) [ "$value" = ethernet ] || ifconfig "$nic" create || return 1 ;;
            X)
                # The shared planner emits only validated native arguments.
                set -f
                set -- $value
                ifconfig "$nic" "$@" || return 1 ;;
            V) ifconfig "$nic" inet6 "$value" || return 1 ;;
        esac
    done < "$XCAT_BOOT_NETWORK_PLAN"
}

xcat_network_check()
{
    [ "${XCAT_BOOT_NETWORK_BASE64:-}" = "${XCAT_BOOTSTRAP_NETWORK_BASE64:-}" ] || return 1
    [ -n "${XCAT_BOOTSTRAP_NETWORK_BASE64:-}" ] || return 0
    xcat_net_bits=$(printf '%s\n' "$XCAT_NETMASK" | awk -F. '{n=0;for(i=1;i<=4;i++){v=$i;while(v){n+=v%2;v=int(v/2)}}print n}') || return 1
    cp "$XCAT_BOOT_NETWORK_PLAN" "$XCAT_WORK/bootstrap.expected" || return 1
    printf 'A\t%s\tinet\t%s\t%s\n' "$XCAT_PROVISIONING_IF" "$XCAT_IPV4" "$xcat_net_bits" >> "$XCAT_WORK/bootstrap.expected"
    ifconfig -a > "$XCAT_WORK/bootstrap.observed" || return 1
    awk -v mode=verify -f /usr/local/libexec/confignetwork-freebsd.awk \
        "$XCAT_WORK/bootstrap.expected" "$XCAT_WORK/bootstrap.observed"
}

xcat_network_target_plan()
{
    xcat_network_plan "$XCAT_BOOTSTRAP_NETWORK_BASE64" "$XCAT_MAC" "$XCAT_WORK/target-bootstrap.plan" || return 1
    awk -F '\t' -v ip="$XCAT_IPV4" -v mask="$XCAT_NETMASK" -v gateway="$XCAT_GATEWAY" '
        BEGIN {
            OFS="\t"; bits=0; split(mask, octets, ".")
            for(i=1;i<=4;i++) {v=octets[i]; while(v) {bits+=v%2;v=int(v/2)}}
        }
        $1=="F" {print "F", "xcat-freebsd-network-1"; next}
        $1=="B" {nic=$2; next}
        $1=="M" {next}
        $1=="C" {print; print "S", "inet", ""; print "S", "inet6", ""; next}
        $1=="K" && $2=="ifconfig_" nic {$3="inet " ip "/" bits " " $3}
        {print}
        END {
            print "A", nic, "inet", ip, bits
            if (gateway!="") {print "D", "inet", gateway; print "K", "defaultrouter", gateway}
        }' "$XCAT_WORK/target-bootstrap.plan" > "$XCAT_WORK/target-network.plan"
}

xcat_network_rc()
{
    xcat_network_target_plan || return 1
    awk -F '\t' '
        BEGIN {print "# BEGIN xCAT FreeBSD network"}
        $1=="C" {print "cloned_interfaces=\"" $2 "\""}
        $1=="K" {print $2 "=\"" $3 "\""}
        END {print "# END xCAT FreeBSD network"}' "$XCAT_WORK/target-network.plan"
}

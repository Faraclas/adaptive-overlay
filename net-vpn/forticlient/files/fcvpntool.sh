#!/bin/bash
# fcvpntool.sh
# FortiClient VPN Helper Script for Gentoo
# Auto-detects and supports both FortiClient 7.0 and 7.2

ROUTES=("10.0.0.0/8" "172.16.0.0/12" "130.164.0.0/17")
DNS_NAMESERVERS=("nameserver 172.18.18.80" "nameserver 172.18.20.80")
DNS_SEARCH="search ni.corp.natinst.com ni.com amer.corp.natinst.com apac.corp.natinst.com emea.corp.natinst.com natinst.com partners.natinst.com aws.natinst.com optimaltestcorp.com ni.systems"
RESOLV_CONF="/etc/resolv.conf"

usage() {
    echo "Usage: $0 [-s|--setup] [-t|--teardown]"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

mode=""
while [[ "$1" != "" ]]; do
    case $1 in
        -s | --setup ) mode="setup" ;;
        -t | --teardown ) mode="teardown" ;;
        * ) usage ;;
    esac
    shift
done

get_vpn_interface() {
    # Check for both 7.2 prefix (fctvpn) and 7.0 prefix (vpn)
    # Using 'ip' command as ifconfig is deprecated
    local interface=""
    local ip_addr=""
    
    # Read output of ip addr to find matching interface
    while read -r line; do
        if [[ "$line" =~ [0-9]+:[[:space:]]+(fctvpn[0-9a-f]+|vpn[0-9a-f]+) ]]; then
            interface="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$interface" && "$line" =~ inet[[:space:]]+([0-9\.]+)/ ]]; then
            ip_addr="${BASH_REMATCH[1]}"
            break
        fi
    done < <(ip -o -4 addr show)

    if [[ -n "$interface" && -n "$ip_addr" ]]; then
        echo "$interface $ip_addr"
    fi
}

do_setup() {
    echo "----- Starting VPN Setup -----"
    local dev_info=$(get_vpn_interface)
    
    if [[ -z "$dev_info" ]]; then
        echo "Error: No FortiClient VPN interface (fctvpn* or vpn*) found! Are you connected?"
        exit 1
    fi
    
    local DEVICE=$(echo "$dev_info" | awk '{print $1}')
    local IPADDRESS=$(echo "$dev_info" | awk '{print $2}')
    
    echo "Found VPN Device: $DEVICE (IP: $IPADDRESS)"
    echo ""
    
    # 1. Check and Apply Routes
    echo "Inspecting routing table..."
    for route in "${ROUTES[@]}"; do
        if ip route show "$route" dev "$DEVICE" 2>/dev/null | grep -q "$route"; then
            echo "  [OK] Route $route is already active."
        else
            echo "  [ADD] Injecting missing route $route..."
            sudo ip route add "$route" via "$IPADDRESS" dev "$DEVICE"
        fi
    done
    echo ""
    
    # 2. Check and Apply DNS
    echo "Inspecting DNS configuration..."
    local dns_needs_update=0
    for ns in "${DNS_NAMESERVERS[@]}"; do
        if ! grep -qxF "$ns" "$RESOLV_CONF"; then
            dns_needs_update=1
        fi
    done
    if ! grep -qxF "$DNS_SEARCH" "$RESOLV_CONF"; then
        dns_needs_update=1
    fi
    
    if [[ $dns_needs_update -eq 1 ]]; then
        echo "  [ADD] Injecting corporate DNS into $RESOLV_CONF..."
        {
            # Place new DNS directives unconditionally at the absolute top for priority
            for ns in "${DNS_NAMESERVERS[@]}"; do
                echo "$ns"
            done
            echo "$DNS_SEARCH"
            
            # Stream the original file, filtering out those exact lines so they don't duplicate
            grep -vF -e "${DNS_NAMESERVERS[0]}" -e "${DNS_NAMESERVERS[1]}" -e "$DNS_SEARCH" "$RESOLV_CONF" 2>/dev/null
        } | sudo tee /tmp/resolv.conf.tmp > /dev/null
        
        sudo mv /tmp/resolv.conf.tmp "$RESOLV_CONF"
        sudo chmod 644 "$RESOLV_CONF"
        echo "  [OK] DNS injected successfully."
    else
        echo "  [OK] DNS configuration is already correct."
    fi
    echo ""
    echo "----- Setup Complete -----"
}

do_teardown() {
    echo "----- Starting VPN Teardown -----"
    
    # 1. Clean up routes
    echo "Inspecting lingering routes..."
    for route in "${ROUTES[@]}"; do
        # Check if route exists at all
        if ip route show "$route" 2>/dev/null | grep -q "$route"; then
            echo "  [REMOVE] Deleting lingering route $route..."
            sudo ip route delete "$route"
        else
            echo "  [OK] Route $route is already cleared."
        fi
    done
    echo ""
    
    # 2. Clean up DNS
    echo "Cleaning up DNS configuration..."
    if grep -qF "ni.corp.natinst.com" "$RESOLV_CONF" || grep -qF "172.18.18.80" "$RESOLV_CONF"; then
        echo "  [REMOVE] Stripping corporate DNS from $RESOLV_CONF..."
        sudo sed -i "\|${DNS_NAMESERVERS[0]}|d" "$RESOLV_CONF"
        sudo sed -i "\|${DNS_NAMESERVERS[1]}|d" "$RESOLV_CONF"
        sudo sed -i "\|$DNS_SEARCH|d" "$RESOLV_CONF"
        echo "  [OK] DNS cleaned successfully."
    else
        echo "  [OK] DNS is already clean."
    fi
    echo ""
    echo "----- Teardown Complete -----"
}

if [[ "$mode" == "setup" ]]; then
    do_setup
elif [[ "$mode" == "teardown" ]]; then
    do_teardown
fi

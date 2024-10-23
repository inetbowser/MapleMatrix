#!/bin/bash

# Inherit from the docker environment or set default
MITM_IFACE="${MITM_IFACE:-wlan0}"
MITM_WLAN="${MITM_WLAN:-yes}"
INTERNET_IFACE="${INTERNET_IFACE:-eth0}"
SSID="${SSID:-Public}"
MAC="${MAC:-random}"
INTERCEPT_HTTPS="${INTERCEPT_HTTPS:-yes}"

# Create some log-related vars
NOW=$(date +%Y-%m-%d_%H-%M-%S)
CAPTURE_FILE="/root/data/dump-$NOW.pcapng"

export SSLKEYLOGFILE="/root/data/sslkeylogfile-$NOW.txt"
touch $SSLKEYLOGFILE

# spoof MAC address
if [ "$MAC" != "unchanged" ] ; then
    ifconfig "$MITM_IFACE" down
    if [ "$MAC" == "random" ] ; then
        echo "using random MAC address"
        macchanger -A "$MITM_IFACE"
    else
        echo "setting MAC address to $MAC"
        macchanger --mac "$MAC" "$MITM_IFACE"
    fi
    if [ ! $? ] ; then
        echo "Failed to change MAC address, aborting."
        exit 1
    fi
    ifconfig "$MITM_IFACE" up
fi

ifconfig "$MITM_IFACE" 10.0.0.1/24

sed -i "s/interface=.*/interface=$MITM_IFACE/g" /etc/dnsmasq.conf

# Start services
/etc/init.d/dbus start
/etc/init.d/dnsmasq start

if [ "$MITM_WLAN" == "yes" ]; then
    # configure WPA password if provided
    if [ ! -z "$PASSWORD" ]; then

      # password length check
      if [ ! ${#PASSWORD} -ge 8 ] && [ ${#PASSWORD} -le 63 ]; then
          echo "PASSWORD must be between 8 and 63 characters"
          echo "password '$PASSWORD' has length: ${#PASSWORD}, exiting."
          exit 1
      fi

      # uncomment WPA2 auth stuff in hostapd.conf
      # replace the password with $PASSWORD
      sed -i 's/#//' /etc/hostapd/hostapd.conf
      sed -i "s/wpa_passphrase=.*/wpa_passphrase=$PASSWORD/g" /etc/hostapd/hostapd.conf
    fi

    # inject values into config templates -- TODO can probably do this at build time...
    sed -i "s/^ssid=.*/ssid=$SSID/g" /etc/hostapd/hostapd.conf
    sed -i "s/interface=.*/interface=$MITM_IFACE/g" /etc/hostapd/hostapd.conf
    /etc/init.d/hostapd start
fi

# Prep system for mitm's transparent mode
# https://docs.mitmproxy.org/stable/howto-transparent/
#
### 1) Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

### 2) Disable ICMP redirects
sysctl -w net.ipv4.conf.all.send_redirects=0

# iptables entries to setup AP network
iptables -t nat -C POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE
if [ ! $? -eq 0 ] ; then
    iptables -t nat -A POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE
fi

iptables -C FORWARD -i "$INTERNET_IFACE" -o "$MITM_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
if [ ! $? -eq 0 ] ; then
    iptables -A FORWARD -i "$INTERNET_IFACE" -o "$MITM_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
fi

iptables -C FORWARD -i "$MITM_IFACE" -o "$INTERNET_IFACE" -j ACCEPT
if [ ! $? -eq 0 ] ; then
    iptables -A FORWARD -i "$MITM_IFACE" -o "$INTERNET_IFACE" -j ACCEPT
fi

#### 3. Create an iptables ruleset that redirects the desired traffic to mitmproxy
iptables -t nat -C PREROUTING -i "$MITM_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
if [ ! $? -eq 0 ] ; then
    iptables -t nat -A PREROUTING -i "$MITM_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
fi

if [ "$INTERCEPT_HTTPS" == "yes" ]; then
    iptables -t nat -C PREROUTING -i "$MITM_IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
    if [ ! $? -eq 0 ] ; then
        iptables -t nat -A PREROUTING -i "$MITM_IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
    fi
fi

ip6tables -t nat -C PREROUTING -i "$MITM_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
if [ ! $? -eq 0 ] ; then
    ip6tables -t nat -A PREROUTING -i "$MITM_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
fi

if [ "$INTERCEPT_HTTPS" == "yes" ]; then
    ip6tables -t nat -C PREROUTING -i "$MITM_IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
    if [ ! $? -eq 0 ] ; then
        ip6tables -t nat -A PREROUTING -i "$MITM_IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
    fi
fi

# All the networking is setup -- lets display our logo :-)
printf "\n\n\n"
cat /root/.logo.ans
printf "\n"

# activate the mitmproxy venv
. mitmproxy-src/venv/bin/activate

# Set up tshark logging
#
# need to do some hax to write to /root
# https://bugzilla.redhat.com/show_bug.cgi?id=850768
echo "tshark: capturing traffic to $CAPTURE_FILE"
tshark -Q -i $MITM_IFACE -w - > "$CAPTURE_FILE" &
TSHARK_PID=$!

#### 4) Fire up mitmweb (in transparent mode)
# options are read automatically from ~/.mitmweb/config.yml
printf "Starting mitm with config:\n"
echo "========================================================================"
cat ~/.mitmproxy/config.yml | grep -v '^ *#' | grep -v -e '^$'
echo "========================================================================"
printf "\n"


# Note that you could switch here to `mitmdump` or `mitmproxy` if desired.
#
# Addons could be used with something like:
#       mitmweb -s /root/mitmproxy-src/mitmproxy/addons/disable_h2c.py
#
# User-created Scripts can be used with something like
#       mitmweb -s /root/scripts/script-name.py

mitmweb
MITMPROXY_PID=$!



#!/usr/bin/env bash
# Simple setup script to configure a Raspberry Pi as an access point with a captive portal.
# Designed for Raspberry Pi OS (64-bit) on a Pi 5. Run after flashing the OS to a USB key or SD card.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

SSID=${SSID:-PiAP}
PASSPHRASE=${PASSPHRASE:-ChangeMe123}
STATIC_IP=${STATIC_IP:-192.168.4.1}
SUBNET=${SUBNET:-192.168.4.0/24}
CHANNEL=${CHANNEL:-7}

apt-get update
apt-get install -y --no-install-recommends hostapd dnsmasq iptables-persistent apache2 php

# Configure static IP for wlan0
grep -q "^interface wlan0" /etc/dhcpcd.conf || cat <<CFG >> /etc/dhcpcd.conf
interface wlan0
    static ip_address=${STATIC_IP}/24
    nohook wpa_supplicant
CFG

service dhcpcd restart

# Configure dnsmasq
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat <<CFG > /etc/dnsmasq.conf
domain-needed
interface=wlan0
dhcp-range=${STATIC_IP%.*}.2,${STATIC_IP%.*}.20,255.255.255.0,24h
CFG

# Configure hostapd
cat <<CFG > /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
CFG

sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Configure simple captive portal page
mkdir -p /var/www/html
cat <<'HTML' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Captive Portal</title>
</head>
<body>
  <h1>Welcome</h1>
  <p>You are connected to the captive portal test build.</p>
</body>
</html>
HTML

systemctl unmask hostapd
systemctl enable --now hostapd dnsmasq apache2

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
netfilter-persistent save

echo "Setup complete. Reboot to start the access point." 

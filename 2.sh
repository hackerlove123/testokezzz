#!/bin/bash
set -e

random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"

echo "Working folder = $WORKDIR"
mkdir -p $WORKDIR
cd $WORKDIR

echo "Detecting IP addresses..."
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IPv4 = $IP4"
echo "IPv6 subnet = $IP6"

read -p "How many proxies to create? Example 500: " COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

echo "Generating proxy data..."
gen_data() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
  done
}

gen_data > $WORKDATA

echo "Generating iptables rules..."
gen_iptables() {
  awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' $WORKDATA
}
gen_iptables > $WORKDIR/boot_iptables.sh
chmod +x $WORKDIR/boot_iptables.sh

echo "Generating IPv6 addresses setup script..."
gen_ifconfig() {
  awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' $WORKDATA
}
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_ifconfig.sh

echo "Creating 3proxy config directory and files..."
mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}

echo "Generating 3proxy config file..."
gen_3proxy() {
  cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" '{printf "%s:CL:%s ", $1, $2}' $WORKDATA)

$(awk -F "/" '{print "auth strong\nallow " $1 "\nproxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\nflush\n"}' $WORKDATA)
EOF
}

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

echo "Creating systemd service for 3proxy..."
cat >/etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=forking
ExecStartPre=/bin/bash $WORKDIR/boot_iptables.sh
ExecStartPre=/bin/bash $WORKDIR/boot_ifconfig.sh
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
LimitNOFILE=10048

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon and enabling service..."
systemctl daemon-reload
systemctl enable 3proxy.service
systemctl restart 3proxy.service

echo "Generating proxy list file..."
awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' $WORKDATA > $WORKDIR/proxy.txt

if ! command -v jq &> /dev/null; then
  echo "jq not found, installing jq..."
  apt-get update && apt-get install -y jq
fi

echo "Creating password-protected zip archive..."
PASS=$(random)
zip --password $PASS proxy.zip proxy.txt > /dev/null

echo "Uploading proxy archive..."
UPLOAD_JSON=$(curl -s -F "file=@proxy.zip" https://file.io)
URL=$(echo "$UPLOAD_JSON" | jq -r '.link // empty')

if [ -z "$URL" ]; then
  echo "Upload failed or no URL returned."
  echo "Response was: $UPLOAD_JSON"
else
  echo "Proxy is ready! Format: IP:PORT:LOGIN:PASS"
  echo "Download zip archive from: $URL"
  echo "Password: $PASS"
fi

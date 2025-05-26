#!/bin/sh

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

install_3proxy() {
  echo "Installing 3proxy latest (v0.9.4)..."
  URL="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz"
  apt-get update -qq
  apt-get install -y gcc make net-tools bsdtar zip curl unzip iptables > /dev/null
  wget -qO- $URL | bsdtar -xvf- > /dev/null
  cd 3proxy-0.9.4 || exit
  make -f Makefile.Linux > /dev/null
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  # Tạo file service systemd cho 3proxy
  cat >/etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure
LimitNOFILE=10048

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable 3proxy
  cd ..
}

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

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\nallow " $1 "\nproxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\nflush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' ${WORKDATA})
EOF
}

install_jq() {
  wget -q -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x ./jq
  mv jq /usr/local/bin/
}

upload_2file() {
  local PASS=$(random)
  zip --password $PASS proxy.zip proxy.txt > /dev/null
  JSON=$(curl -s -F "file=@proxy.zip" https://file.io)
  URL=$(echo "$JSON" | jq --raw-output '.link')

  echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
  echo "Download zip archive from: ${URL}"
  echo "Password: ${PASS}"
}

gen_data() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
  done
}

gen_iptables() {
  cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' ${WORKDATA})
EOF
}

echo "Installing required packages..."
apt-get update -qq
apt-get install -y gcc net-tools bsdtar zip curl iptables iproute2 > /dev/null

install_3proxy

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR || exit

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IPv4 = ${IP4}, External IPv6 prefix = ${IP6}"

echo "How many proxies do you want to create? Example 500"
read -r COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

gen_data > $WORKDATA
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh

chmod +x $WORKDIR/boot_*.sh

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

# Cấu hình tự khởi động
if ! grep -q "$WORKDIR/boot_iptables.sh" /etc/rc.local 2>/dev/null; then
  echo "bash $WORKDIR/boot_iptables.sh" >> /etc/rc.local
  echo "bash $WORKDIR/boot_ifconfig.sh" >> /etc/rc.local
  echo "ulimit -n 10048" >> /etc/rc.local
  echo "systemctl start 3proxy" >> /etc/rc.local
fi

bash /etc/rc.local

gen_proxy_file_for_user

install_jq && upload_2file

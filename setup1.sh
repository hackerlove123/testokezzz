#!/bin/bash
set -e

random() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c5
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
  ip64() {
    echo "${array[RANDOM % 16]}${array[RANDOM % 16]}${array[RANDOM % 16]}${array[RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_dependencies() {
  echo "Installing required packages..."
  apt update
  apt install -y gcc net-tools zip libarchive-tools wget curl jq iptables
}

install_3proxy() {
  echo "Installing 3proxy latest (v0.9.4)..."
  URL="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz"
  wget -qO- $URL | tar -xzf -
  cd 3proxy-0.9.4
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cp ./scripts/rc.d/3proxy.sh /etc/init.d/3proxy || cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
  chmod +x /etc/init.d/3proxy
  update-rc.d 3proxy defaults
  cd ..
  rm -rf 3proxy-0.9.4
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
  awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA} > proxy.txt
}

upload_2file() {
  PASS=$(random)
  zip --password $PASS proxy.zip proxy.txt
  JSON=$(curl -s -F "file=@proxy.zip" https://file.io)
  URL=$(echo "$JSON" | jq -r '.link')
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
  awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA} > boot_iptables.sh
  chmod +x boot_iptables.sh
}

gen_ifconfig() {
  awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' ${WORKDATA} > boot_ifconfig.sh
  chmod +x boot_ifconfig.sh
}

main() {
  echo "Starting proxy installer..."

  install_dependencies
  install_3proxy

  WORKDIR="/home/proxy-installer"
  WORKDATA="${WORKDIR}/data.txt"
  mkdir -p $WORKDIR
  cd $WORKDIR

  IP4=$(curl -4 -s icanhazip.com)
  IP6=$(curl -6 -s icanhazip.com | cut -d: -f1-4)

  echo "Detected IPv4: $IP4"
  echo "Detected IPv6 subnet: $IP6"

  read -p "How many proxies do you want to create? Example 500: " COUNT
  FIRST_PORT=10000
  LAST_PORT=$((FIRST_PORT + COUNT - 1))

  gen_data > $WORKDATA
  gen_iptables
  gen_ifconfig

  gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

  # Setup rc.local if not exists
  if [ ! -f /etc/rc.local ]; then
    echo -e "#!/bin/bash\nexit 0" > /etc/rc.local
    chmod +x /etc/rc.local
  fi

  # Insert startup commands before 'exit 0'
  sed -i '/^exit 0/i bash '"${WORKDIR}"'/boot_iptables.sh\nbash '"${WORKDIR}"'/boot_ifconfig.sh\nulimit -n 10048\nservice 3proxy start\n' /etc/rc.local

  # Run now
  bash /etc/rc.local

  gen_proxy_file_for_user

  upload_2file
}

main

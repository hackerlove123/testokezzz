#!/bin/bash

# Hàm tạo chuỗi ngẫu nhiên
tao_ngau_nhien() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Mảng ký tự thập lục phân
mang_hex=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Hàm tạo địa chỉ IPv6
tao_ipv6() {
  tao64() {
    echo "${mang_hex[$RANDOM % 16]}${mang_hex[$RANDOM % 16]}${mang_hex[$RANDOM % 16]}${mang_hex[$RANDOM % 16]}"
  }
  echo "$1:$(tao64):$(tao64):$(tao64):$(tao64)"
}

# Cài đặt 3proxy
cai_3proxy() {
  echo "🔧 Đang cài đặt 3proxy..."
  URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
  wget -qO- $URL | bsdtar -xvf-
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
  chmod +x /etc/init.d/3proxy
  systemctl enable 3proxy
  cd "$THU_MUC_LAM_VIEC"
}

# Tạo file cấu hình 3proxy
tao_cau_hinh_3proxy() {
  cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${DU_LIEU})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${DU_LIEU})
EOF
}

# Xuất file proxy.txt cho người dùng
xuat_file_proxy() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${DU_LIEU})
EOF
}

# Cài jq
cai_jq() {
  wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x ./jq
  cp jq /usr/bin
}

# Tải proxy.txt lên file.io
tai_len_file() {
  local MAT_KHAU=$(tao_ngau_nhien)
  zip --password $MAT_KHAU proxy.zip proxy.txt
  JSON=$(curl -F "file=@proxy.zip" https://file.io)
  LINK=$(echo "$JSON" | jq --raw-output '.link')

  echo "✅ Proxy đã sẵn sàng! Định dạng IP:PORT:TÊN:MK"
  echo "📥 Tải xuống tại: ${LINK}"
  echo "🔑 Mật khẩu giải nén: ${MAT_KHAU}"
}

# Sinh dữ liệu người dùng proxy
sinh_du_lieu() {
  seq $PORT_DAU $PORT_CUOI | while read port; do
    echo "nguoi$(tao_ngau_nhien)/mk$(tao_ngau_nhien)/$IPV4/$port/$(tao_ipv6 $IPV6)"
  done
}

# Sinh iptables mở cổng
sinh_iptables() {
  cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${DU_LIEU})
EOF
}

# Cấu hình địa chỉ IPv6
sinh_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${DU_LIEU})
EOF
}

# ======== BẮT ĐẦU CHƯƠNG TRÌNH CHÍNH =========

echo "🌐 Cài các gói cần thiết..."
yum -y install gcc net-tools bsdtar zip curl >/dev/null

# Tạo rc.local nếu chưa có
if [ ! -f /etc/rc.local ]; then
  echo '#!/bin/bash' > /etc/rc.local
  chmod +x /etc/rc.local
  ln -s /etc/rc.local /etc/rc.d/rc.local
  cat <<EOF > /etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable rc-local
fi

# Cài proxy
cai_3proxy

# Khởi tạo thư mục làm việc
echo "📁 Thư mục làm việc = /home/cai-proxy"
THU_MUC_LAM_VIEC="/home/cai-proxy"
DU_LIEU="${THU_MUC_LAM_VIEC}/du_lieu.txt"
mkdir -p "$THU_MUC_LAM_VIEC" && cd "$THU_MUC_LAM_VIEC"

# Lấy IP hệ thống
IPV4=$(curl -4 -s icanhazip.com)
IPV6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "🔎 IP nội bộ = ${IPV4}"
echo "🔎 Subnet IPv6 = ${IPV6}"

echo "📌 Bạn muốn tạo bao nhiêu proxy? (VD: 100)"
read SO_LUONG

PORT_DAU=10000
PORT_CUOI=$(($PORT_DAU + $SO_LUONG))

sinh_du_lieu >"$DU_LIEU"
sinh_iptables >boot_iptables.sh
sinh_ifconfig >boot_ifconfig.sh
chmod +x boot_*.sh

tao_cau_hinh_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Ghi vào rc.local để khởi động lại khi reboot
cat >>/etc/rc.local <<EOF
bash ${THU_MUC_LAM_VIEC}/boot_iptables.sh
bash ${THU_MUC_LAM_VIEC}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local

# Xuất file proxy.txt và upload
xuat_file_proxy
cai_jq && tai_len_file

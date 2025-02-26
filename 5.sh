#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh")
}
setup_ipv6

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
    echo "Cài đặt 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 5000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth none
authcache 86400
allow * 192.168.0.0/16
allow * 127.0.0.1

$(awk -F "/" '{print "\n" \
"allow * " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4}' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
        echo "$IP4:$port" >> "$WORKDIR/ipv4.txt"
        new_ipv6=$(gen64 $IP6)
        echo "$new_ipv6" >> "$WORKDIR/ipv6.txt"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

echo "Cài đặt các ứng dụng cần thiết"
yum -y install wget gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "Thư mục làm việc = /home/vlt"
WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(hostname -I | awk '{print $1}')
IP6=$(ip addr show eth0 | grep 'pinet6 ' | awk '{print $2}' | cut -f1-4 -d':' | grep '^2')

echo "IPv4 = ${IP4}"
echo "IPv6 = ${IP6}"

while true; do
  read -p "Nhập số lượng muốn tạo: " PORT_COUNT
  if [[ $PORT_COUNT =~ ^[0-9]+$ ]] && ((PORT_COUNT > 0)); then
    echo "Số lượng hợp lệ."
    while true; do
      read -p "Nhập cổng bắt đầu: " FIRST_PORT
      if [[ $FIRST_PORT =~ ^[0-9]+$ ]] && ((FIRST_PORT >= 10000 && FIRST_PORT <= 80000)); then
        echo "Cổng bắt đầu hợp lệ: $FIRST_PORT."
        LAST_PORT=$((FIRST_PORT + PORT_COUNT - 1))
        echo "Dải cổng từ $FIRST_PORT đến $LAST_PORT."
        break 2
      else
        echo "Cổng bắt đầu không hợp lệ. Vui lòng nhập một số từ 10000 đến 80000."
      fi
    done
  else
    echo "Số lượng không hợp lệ. Vui lòng nhập một số nguyên dương."
  fi
done
echo "Cổng proxy: $FIRST_PORT"
echo "Số lượng tạo: $(($LAST_PORT - $FIRST_PORT + 1))"

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg
cat >>/etc/rc.local <<EOF

systemctl start NetworkManager.service
killall 3proxy
service 3proxy start
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -u unlimited -n 999999 -s 16384
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chmod +x /etc/rc.d/rc.local
cat >>/etc/rc.local <<EOF

systemctl start NetworkManager.service
killall 3proxy
service 3proxy start
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -u unlimited -n 999999 -s 16384
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

# Thêm các lệnh định tuyến vào /etc/rc.local
cat >> /etc/rc.local <<EOF
ip route add 192.168.1.151/32 dev ppp1
ip route add 192.168.1.29/32 via 203.210.144.132
ip route add 192.168.1.3/32 via 203.210.144.132
ip route add 203.210.144.132/32 dev ppp1
ip route add 192.168.1.0/24 dev bro
ip route add 127.0.0.0/16 dev lo
ip route add 0.0.0.0/0 via 203.210.144.132 dev ppp1
EOF

bash /etc/rc.local
gen_proxy_file_for_user
rm -rf /root/3proxy-3proxy-0.8.6
echo "Starting Proxy"
echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
systemctl stop firewalld
systemctl disable firewalld
sudo systemctl stop firewalld

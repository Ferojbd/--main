#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Lấy tên giao diện mạng
interface=$(ip -o -4 route show to default | awk '{print $5}')

# Xoá toàn bộ địa chỉ IPv6 trên giao diện mạng
setup_ipv6() {
    echo "Xoá IPv6.."
    ip -6 addr flush dev "$interface"
}

setup_ipv6

# Kiểm tra hệ điều hành để quyết định cách cấu hình
if [ -f /etc/centos-release ]; then
    # CentOS

    # Kiểm tra sự tồn tại của YUM
    YUM=$(which yum)
    if [ -n "$YUM" ]; then
        # Cấu hình IPv6 cho CentOS

        # Xóa nội dung của /etc/sysctl.conf và thêm cấu hình IPv6
        echo > /etc/sysctl.conf
        tee -a /etc/sysctl.conf <<EOF
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
EOF

        # Tải lại cấu hình sysctl
        sysctl -p

        # Lấy phần IP3 và IP4 từ địa chỉ IPv4 hiện tại
        IPC=$(curl -4 -s icanhazip.com | cut -d"." -f3)
        IPD=$(curl -4 -s icanhazip.com | cut -d"." -f4)

        # Tìm tên giao diện mạng
        INTERFACE=$(ls /sys/class/net | grep -E 'e|eth')

        # Cấu hình file ifcfg-eth0 dựa trên giá trị của IPC
        if [ "$IPC" == "4" ]; then
            IPV6_ADDRESS="2403:6a40:0:40::$IPD:0000/64"
            IPV6_DEFAULTGW="2403:6a40:0:40::1"
        elif [ "$IPC" == "5" ]; then
            IPV6_ADDRESS="2403:6a40:0:41::$IPD:0000/64"
            IPV6_DEFAULTGW="2403:6a40:0:41::1"
        elif [ "$IPC" == "244" ]; then
            IPV6_ADDRESS="2403:6a40:2000:244::$IPD:0000/64"
            IPV6_DEFAULTGW="2403:6a40:2000:244::1"
        else
            IPV6_ADDRESS="2403:6a40:0:$IPC::$IPD:0000/64"
            IPV6_DEFAULTGW="2403:6a40:0:$IPC::1"
        fi

        # Tạo hoặc chỉnh sửa file ifcfg-eth0
        tee -a "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" <<-EOF
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=$IPV6_ADDRESS
IPV6_DEFAULTGW=$IPV6_DEFAULTGW
EOF

        # Khởi động lại dịch vụ mạng để áp dụng cấu hình
        service network restart

        echo "Cấu hình IPv6 cho CentOS hoàn tất."
    else
        echo "Không tìm thấy YUM trên hệ thống."
        exit 1
    fi

elif [ -f /etc/lsb-release ]; then
    # Ubuntu

    # Cấu hình IPv6 cho Ubuntu
    echo "Cấu hình IPv6 cho Ubuntu..."

    # Lấy IPv4 hiện tại và phần IP3, IP4 từ nó
    ipv4=$(curl -4 -s icanhazip.com)
    IPC=$(echo "$ipv4" | cut -d"." -f3)
    IPD=$(echo "$ipv4" | cut -d"." -f4)

    # Lấy tên giao diện mạng phù hợp
    INTERFACE=$(ls /sys/class/net | grep 'e')

    # Cấu hình địa chỉ IPv6 và gateway dựa trên giá trị của IPC
    if [ "$IPC" == "4" ]; then
        IPV6_ADDRESS="2403:6a40:0:40::$IPD:0000/64"
        GATEWAY="2403:6a40:0:40::1"
    elif [ "$IPC" == "5" ]; then
        IPV6_ADDRESS="2403:6a40:0:41::$IPD:0000/64"
        GATEWAY="2403:6a40:0:41::1"
    elif [ "$IPC" == "244" ]; then
        IPV6_ADDRESS="2403:6a40:2000:244::$IPD:0000/64"
        GATEWAY="2403:6a40:2000:244::1"
    else
        IPV6_ADDRESS="2403:6a40:0:$IPC::$IPD:0000/64"
        GATEWAY="2403:6a40:0:$IPC::1"
    fi

    # Xác định đường dẫn tệp cấu hình Netplan phù hợp
    if [ "$INTERFACE" == "ens160" ]; then
        NETPLAN_PATH="/etc/netplan/99-netcfg-vmware.yaml"
    elif [ "$INTERFACE" == "eth0" ]; then
        NETPLAN_PATH="/etc/netplan/50-cloud-init.yaml"
    else
        echo "Không tìm thấy card mạng phù hợp."
        exit 1
    fi

    # Đọc và cập nhật tệp cấu hình Netplan
    NETPLAN_CONFIG=$(cat "$NETPLAN_PATH")
    NEW_NETPLAN_CONFIG=$(sed "/gateway4:/i \ \ \ \ \ \ \  - $IPV6_ADDRESS" <<< "$NETPLAN_CONFIG")
    NEW_NETPLAN_CONFIG=$(sed "/gateway4:.*/a \ \ \ \ \  gateway6: $GATEWAY" <<< "$NEW_NETPLAN_CONFIG")
    echo "$NEW_NETPLAN_CONFIG" > "$NETPLAN_PATH"

    # Áp dụng cấu hình Netplan
    sudo netplan apply

    echo "Cấu hình IPv6 cho Ubuntu hoàn tất."
fi

echo "Giao diện mạng: $interface"
echo "Đã cấu hình IPv6 thành công!"

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
    echo "Installing 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.13.tar.gz"
    wget -qO- $URL | tar -xz
    cd 3proxy-0.8.13 || exit 1
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd $WORKDIR 
    systemctl daemon-reload
    systemctl enable 3proxy
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    echo "net.ipv6.conf.${interface}.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
    systemctl stop firewalld
    systemctl disable firewalld
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 10000
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
allow 103.191.241.5
allow 127.0.0.1

$(awk -F "/" '{print "\n" \
"auth none\n" \
"allow *\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat > proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4}' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        entry="//$IP4/$port/$(gen64 $IP6)"
        echo "$entry"
        echo "$IP4:$port" >> "$WORKDIR/ipv4.txt"
        echo "$(gen64 $IP6)" >> "$WORKDIR/ipv6.txt"
    done > $WORKDATA
}

gen_iptables() {
    cat <<EOF > $WORKDIR/boot_iptables.sh
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF > $WORKDIR/boot_ifconfig.sh
$(awk -F "/" '{print "ifconfig $interface inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

echo "Installing necessary packages..."
yum -y install wget gcc net-tools bsdtar zip >/dev/null 2>&1

WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IPv4 = ${IP4}"
echo "IPv6 = ${IP6}"

read -p "Nhập số lượng muốn tạo: " PORT_COUNT

if [[ $PORT_COUNT =~ ^[0-9]+$ && $PORT_COUNT -gt 0 ]]; then
echo "Đang tạo $PORT_COUNT cổng port..."
FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + PORT_COUNT - 1))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
systemctl start NetworkManager.service
ifup $interface
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

# Tạo file dịch vụ systemd cho 3proxy
cat <<EOF >/etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Tạo file dịch vụ systemd cho rc.local nếu chưa có
cat <<EOF >/etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

chmod +x /etc/rc.local
bash /etc/rc.local

gen_proxy_file_for_user
rm -rf /root/3proxy-0.8.13

    echo "Starting Proxy"
else
    echo "Số không hợp lệ, vui lòng thử lại."
fi

# Hiển thị tổng số IPv6 hiện tại
echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l

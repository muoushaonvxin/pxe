#!/bin/bash
#

# 关闭selinux 和 iptables
function stop_selinux_iptables(){
	sed -i 's/SELINUX=enforcing/SELINUX=disable/' /etc/selinux/config
	setenforce 0
	# systemctl stop firewalld
	# systemctl disable firewalld
	service iptables stop	
}

# 检测有没有安装dhcp
function check_dhcp(){
	if [ `rpm -q dhcp` == "package dhcp is not installed" ]; then
		yum -y install -q dhcp
	elif [ `rpm -qa | grep dhcp | grep -v -E \(libs\|common\)` == `rpm -q dhcp` ]; then
		echo "dhcp is already installed. "
	fi
}

# 检测有没有安装tftp
function check_tftp(){	
	if [ `rpm -q tftp` == "package tftp is not installed" ]; then
		yum -y install -q tftp xinetd tftp-server syslinux
	elif [ `rpm -qa | grep tftp` == `rpm -q tftp` ]; then
		echo "tftp is already installed. "
	fi
}

function check_httpd(){	
	if [ `rpm -q httpd` == "package httpd is not installed" ]; then
		yum -y install -q httpd 
	elif [ `rpm -qa httpd` == `rpm -q httpd` ]; then
		echo "httpd is already installed. "
	fi
}

# 检测dhcp的配置文件
function check_dhcp_cfg(){
>/etc/dhcp/dhcpd.conf

	cat > /etc/dhcp/dhcpd.conf << EOF
allow booting;
allow bootp;

subnet 192.168.137.0 netmask 255.255.255.0 {
	range 192.168.137.50 192.168.137.70;
    option domain-name-servers ns1.internal.example.org;
	option domain-name "internal.example.org";
	option routers 192.168.137.1;
  	option broadcast-address 192.168.137.255;
    default-lease-time 600;
	max-lease-time 7200;
 	next-server 192.168.137.250;
    filename "pxelinux.0";
}
EOF

systemctl start dhcpd

RETVAL=$?

if [ $RETVAL -ne 0 ]; then
	echo "dhcp_cfg have syntax error.."
	return 1
fi

}

# 检测tftp的配置文件
function check_tftp_cfg(){
sed -i '/disable/s/yes/no/' /etc/xinetd.d/tftp
cp -r /usr/share/syslinux/pxelinux.0 /var/lib/tftpboot
mkdir /var/lib/tftpboot/pxelinux.cfg &> /dev/null
touch /var/lib/tftpboot/pxelinux.cfg/default
>/var/lib/tftpboot/pxelinux.cfg/default

	cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
default vesamenu.c32
timeout 600 

display boot.msg
menu clear
menu background splash.jpg

menu title Community Enterprise operating system 6.8 
label linux
	menu label ^Install Community Enterprise operating system 6.8 
	kernel vmlinuz
	append initrd=initrd.img ks=http://192.168.137.250/ks.cfg
label local
    menu label Boot from ^local drive
    menu default
    localboot 0xffff
EOF

cp /mnt/cdrom/isolinux/boot.msg /var/lib/tftpboot
cp /mnt/cdrom/isolinux/initrd.img /var/lib/tftpboot
cp /mnt/cdrom/isolinux/splash.jpg /var/lib/tftpboot
cp /mnt/cdrom/isolinux/vmlinuz /var/lib/tftpboot

systemctl start xinetd
}


function check_ks_cfg(){
	cat > /var/www/html/ks.cfg << EOF
#platform=x86, AMD64, or Intel EM64T
#version=DEVEL
# Firewall configuration
	firewall --disabled
# Install OS instead of upgrade
	install
# Use network installation
	url --url="http://192.168.0.250/dvd/"
# Root password
	rootpw --plaintext 123456
# System authorization information
	auth  --useshadow  --passalgo=sha512
# Use graphical install
	graphical
	firstboot --disable
# System keyboard
	keyboard us
# System language
	lang en_US
# SELinux configuration
	selinux --disabled
# Installation logging level
	logging --level=info

# System timezone
timezone  Asia/Shanghai
# Network information
network  --bootproto=dhcp --device=eth0 --onboot=on
# System bootloader configuration
bootloader --location=mbr
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all  
# Disk partitioning information
part /boot --fstype="ext4" --size=200
part / --fstype="ext4" --size=20000
part swap --fstype="swap" --size=8192

%packages
@additional-devel
@development
git
wget
@core
%end

EOF

mkdir /var/www/html/dvd
mount -o loop /home/iso/CentOS-6.8-x86_64-bin-DVD1.iso /var/www/html/dvd
systemctl restart httpd

}


# 所有函数顺序执行
function main(){
	stop_selinux_iptables
	check_dhcp	
	check_tftp
	check_httpd
	check_dhcp_cfg
	check_tftp_cfg
	check_ks_cfg
}

main

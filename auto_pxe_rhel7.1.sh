#!/bin/bash
#

# 关闭selinux 和 iptables
function stop_selinux_iptables(){
	sed -i 's/SELINUX=enforcing/SELINUX=disable/' /etc/selinux/config
	setenforce 0
	systemctl stop firewalld
	systemctl disable firewalld
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

subnet 192.168.0.0 netmask 255.255.255.0 {
	range 192.168.0.10 192.168.0.50;
    option domain-name-servers ns1.internal.example.org;
	option domain-name "internal.example.org";
	option routers 192.168.0.1;
  	option broadcast-address 192.168.0.255;
    default-lease-time 600;
	max-lease-time 7200;
 	next-server 192.168.0.250;
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
menu background splash.png
menu title Red Hat Enterprise Linux 7.1 

label linux
	menu label ^Install Red Hat Enterprise Linux 7.1 
	kernel vmlinuz
	append initrd=initrd.img ks=http://192.168.0.250/ks.cfg
label local
    menu label Boot from ^local drive
    menu default
    localboot 0xffff
EOF

cp /mnt/rhel7.1/x86_64/dvd/isolinux/boot.msg /var/lib/tftpboot
cp /mnt/rhel7.1/x86_64/dvd/isolinux/initrd.img /var/lib/tftpboot
cp /mnt/rhel7.1/x86_64/dvd/isolinux/splash.png /var/lib/tftpboot
cp /mnt/rhel7.1/x86_64/dvd/isolinux/vmlinuz /var/lib/tftpboot

systemctl start xinetd
}


function check_ks_cfg(){
	cat > /var/www/html/ks.cfg << EOF
#version=RHEL7
# System authorization information
	auth --enableshadow --passalgo=sha512
# Reboot after installation
	reboot
# Use network installation
	url --url="http://192.168.0.250/dvd/"
# Use graphical install
	text
# Firewall configuration
	firewall --enabled --service=ssh
	firstboot --disable
	ignoredisk --only-use=vda
# Keyboard layouts
# old format: keyboard us
# new format:
	keyboard --vckeymap=us --xlayouts='us'
# System language
	lang en_US.UTF-8

# Network information
network  --bootproto=dhcp
network  --hostname=zhangyz
# Root password
rootpw --plaintext redhat
# SELinux configuration
selinux --enforcing
# System services
services --disabled="kdump,rhsmcertd" --enabled="network,sshd,rsyslog,ovirt-guest-agent,chronyd"
# System timezone
timezone America/New_York --isUtc
# System bootloader configuration
bootloader --append="console=tty0 crashkernel=auto" --location=mbr --timeout=1 --boot-drive=vda
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all --initlabel 
# Disk partitioning information
part / --fstype="xfs" --ondisk=vda --size=6144


# workaround anaconda requirements
%post
useradd carol
echo 123456 | passwd --stdin carol
%end

%packages
@core
%end

EOF

mkdir /var/www/html/dvd &> /dev/null
mkdir /home/iso &> /dev/null
mount -o loop /home/iso/rhel7.1/x86_64/isos/rhel-server-7.1-x86_64-dvd.iso /var/www/html/dvd
systemctl restart httpd

}


# 所有函数顺序执行
function init_start(){
	stop_selinux_iptables
	check_dhcp	
	check_tftp
	check_httpd
	check_dhcp_cfg
	check_tftp_cfg
	check_ks_cfg
}

function start() {
	mount -o loop /home/iso/rhel7.1/x86_64/isos/rhel-server-7.1-x86_64-dvd.iso /var/www/html/dvd &> /dev/null
	/etc/init.d/dhcpd start &> /dev/null
	/etc/init.d/xinetd start &> dev/null
	/etc/init.d/httpd start &> /dev/null
}

function stop() {
	umount /var/www/html/dvd &> /dev/null
	/etc/init.d/dhcpd stop &> /dev/null
	/etc/init.d/xinetd stop &> /dev/null
	/etc/init.d/httpd stop &> /dev/null	
}

case "$1" in
	init_start)
		init_start
	;;
	start)
		start
	;;
	stop)
		stop
	;;
	*)
		echo "Usage: `basename $0` { init_start | start | stop }."
	;;
esac


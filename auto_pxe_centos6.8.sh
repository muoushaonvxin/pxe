#!/bin/bash
#

function stop_selinux_iptables(){
        sed -i 's/SELINUX=enforcing/SELINUX=disable/' /etc/selinux/config
        setenforce 0
        service iptables stop
}

function check_dhcp(){
        yum -y install -q dhcp &> /dev/null
}

function check_tftp(){
        yum -y install -q tftp xinetd tftp-server syslinux &> /dev/null
}

function check_httpd(){
        yum -t install -q httpd &> /dev/null
}

function check_dhcp_cfg(){
> /etc/dhcp/dhcpd.conf

cat > /etc/dhcp/dhcpd.conf << EOF
allow booting;
allow bootp;

subnet 192.168.99.0 netmask 255.255.255.0 {
        range 192.168.99.50 192.168.99.70;
        option domain-name-servers ns1.internal.example.org;
        option domain-name "internal.example.org";
        option routers 192.168.99.1;
        option broadcast-address 192.168.99.255;
        default-lease-time 600;
        max-lease-time 7200;
        next-server 192.168.99.235;
        filename "pxelinux.0";
}
EOF

/etc/init.d/dhcpd start

RETVAL=$?

if [ $RETVAL -ne 0 ]; then
        echo "dhcp_cfg have syntax error.."
        return 1
fi

}

function check_tftp_cfg(){
sed -i '/disable/s/yes/no/' /etc/xinetd.d/tftp
cp -r /mnt/cdrom/isolinux/vesamenu.c32 /var/lib/tftpboot/
cp -r /usr/share/syslinux/pxelinux.0 /var/lib/tftpboot
mkdir /var/lib/tftpboot/pxelinux.cfg &> /dev/null
touch /var/lib/tftpboot/pxelinux.cfg/default

> /var/lib/tftpboot/pxelinux.cfg/default 

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
        append initrd=initrd.img ks=http://192.168.99.235/ks.cfg
label local
        menu label Boot from ^local drive
        menu default
        localboot 0xffff
EOF

cp /mnt/cdrom/isolinux/boot.msg /var/lib/tftpboot
cp /mnt/cdrom/isolinux/initrd.img /var/lib/tftpboot
cp /mnt/cdrom/isolinux/splash.jpg /var/lib/tftpboot
cp /mnt/cdrom/isolinux/vmlinuz /var/lib/tftpboot

service xinetd restart
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
                url --url="http://192.168.99.235/dvd/"
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

mkdir /var/www/html/dvd &> /dev/null
mkdir /home/iso &> /dev/null && wget 
mount -o loop /home/iso/CentOS-6.8-x86_64-bin-DVD1.iso /var/www/html/dvd
service httpd restart

}

function main_init(){
        stop_selinux_iptables
        check_dhcp
        check_tftp
        check_httpd
        check_dhcp_cfg
        check_tftp_cfg
        check_ks_cfg
}

function main_start(){
        /etc/init.d/dhcpd start
        /etc/init.d/xinetd start
        /etc/init.d/httpd start
}

function main_stop(){
        /etc/init.d/dhcpd stop
        /etc/init.d/xinetd stop
        /etc/init.d/httpd stop
}

case "$1" in
        init)
                main_init
        ;;
        start)
                main_start
        ;;
        stop)
                main_stop
        ;;
        *)
                echo "Usage: `basename $0` { init | start | stop }."
        ;;
esac

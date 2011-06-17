root=1
rootok=1
netroot=xcat
clear
echo "Wating for network to become available..."
echo '[ -e $NEWROOT/proc ]' > /initqueue-finished/xcatroot.sh
#/bin/dash
mkdir -p /etc/ssh
mkdir -p /var/empty/sshd
echo sshd:x:30:30:SSH User:/var/empty/sshd:/sbin/nologin >> /etc/passwd
ssh-keygen -q -t rsa -f /etc/ssh/ssh_host_rsa_key -C '' -N ''
ssh-keygen -q -t dsa -f /etc/ssh/ssh_host_dsa_key -C '' -N ''
echo 'Protocol 2' >> /etc/ssh/sshd_config
/usr/sbin/sshd

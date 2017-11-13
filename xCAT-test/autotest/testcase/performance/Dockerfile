FROM alpine:latest
MAINTAINER binxu <bxuxa@cn.ibm.com>
RUN apk add --update openssh bash wget && \
 ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa && \
 sed -i "s/UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g" /etc/ssh/sshd_config && sed -i "s/UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config && sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config && sed -i "s/#AuthorizedKeysFile/AuthorizedKeysFile/g" /etc/ssh/sshd_config && \
 echo "root:cluster" | chpasswd
EXPOSE 22
CMD ["/usr/sbin/sshd","-D", "-o PermitRootLogin=yes"]

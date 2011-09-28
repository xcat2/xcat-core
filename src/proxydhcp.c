#include <stdio.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <stdlib.h>
#include <errno.h>
#include <netinet/in.h>
int main() {
	int serverfd,port;
	int getpktinfo = 1;
	struct addrinfo hint, *res;
	char cmsg[CMSG_SPACE(sizeof(struct in_pktinfo))];
	char clientpacket[1024];
	struct sockaddr_in clientaddr;
	struct msghdr msg;
	struct cmsghdr *cmsgptr;
	struct iovec iov[1];
	unsigned int myip;
	char *txtptr;
	iov[0].iov_base = clientpacket;
	iov[0].iov_len = 1024;
	memset(&msg,0,sizeof(msg));
	memset(&clientaddr,0,sizeof(clientaddr));
	msg.msg_name=&clientaddr;
	msg.msg_namelen = sizeof(clientaddr);
	msg.msg_iov = iov;
	msg.msg_iovlen = 1;
	msg.msg_control=&cmsg;
	msg.msg_controllen = sizeof(cmsg);
	
	
	char bootpmagic[4] = {0x63,0x82,0x53,0x63};
	int pktsize;
	int doexit=0;
	port = 4011;
	memset(&hint,0,sizeof(hint));
	hint.ai_family = PF_INET;  /* Would've done UNSPEC, but it doesn't work right and this is heavily v4 specific anyway */
	hint.ai_socktype = SOCK_DGRAM;
	hint.ai_flags = AI_PASSIVE;
	getaddrinfo(NULL,"4011",&hint,&res);
	serverfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
	if (!serverfd) { fprintf(stderr,"That's odd...\n"); }
	setsockopt(serverfd,IPPROTO_IP,IP_PKTINFO,&getpktinfo,sizeof(getpktinfo));
	if (bind(serverfd,res->ai_addr ,res->ai_addrlen) < 0) {
		fprintf(stderr,"Unable to bind 4011");
		exit(1);
	}
	while (!doexit) {
		pktsize = recvmsg(serverfd,&msg,0);
		if (pktsize < 320) {
			continue;
		}
		if (clientpacket[0] != 1 || memcmp(clientpacket+0xec,bootpmagic,4)) {
			continue;
		}
		for (cmsgptr = CMSG_FIRSTHDR(&msg); cmsgptr != NULL; cmsgptr = CMSG_NXTHDR(&msg,cmsgptr)) {
			if (cmsgptr->cmsg_level == IPPROTO_IP && cmsgptr->cmsg_type == IP_PKTINFO) {
				myip = ((struct in_pktinfo*)(CMSG_DATA(cmsgptr)))->ipi_addr.s_addr;
			}
		}
		clientpacket[0] = 2; //change to a reply
		myip = htonl(myip); //endian neutral change
		clientpacket[0x14] = (myip>>24)&0xff; //maybe don't need to do this, maybe assigning the whole int would be better
		clientpacket[0x15] = (myip>>16)&0xff;
		clientpacket[0x16] = (myip>>8)&0xff;
		clientpacket[0x17] = (myip)&0xff;
		txtptr = clientpacket+0x6c;
		strncpy(txtptr,"bootmgfw.efi",128); // keeping 128 in there just in case someone changes the string
		clientpacket[0xf0]=0x35; //DHCP MSG type 
		clientpacket[0xf1]=0x1; // LEN of 1
		clientpacket[0xf2]=0x5; //DHCP ACK
		clientpacket[0xf3]=0x36; //DHCP server identifier
		clientpacket[0xf4]=0x4; //DHCP server identifier length
		clientpacket[0xf5] = (myip>>24)&0xff; //maybe don't need to do this, maybe assigning the whole int would be better
		clientpacket[0xf6] = (myip>>16)&0xff;
		clientpacket[0xf7] = (myip>>8)&0xff;
		clientpacket[0xf8] = (myip)&0xff;
		clientpacket[0xf9] = 0xfc; // dhcp 252 'proxy', but coopeted by bootmgfw, it's actually suggesting the boot config file
		clientpacket[0xfa] = 9; //length of 9
		txtptr = clientpacket+0xfb;
		strncpy(txtptr,"Boot/BCD",8);
		clientpacket[0x103]=0;
		clientpacket[0x104]=0xff;
		sendto(serverfd,clientpacket,pktsize,0,(struct sockaddr*)&clientaddr,sizeof(clientaddr));
	}
}


	
	

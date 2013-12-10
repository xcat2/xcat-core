#include <stdio.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <stdlib.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <syslog.h>

// the chunk size for each alloc 
int chunknum = 200;
int doreload = 0;
int verbose = 0;
char logmsg[50];

// the struct to store the winpe configuration for each node
struct nodecfg {
    char node[50];
    char data[150];
};

char *data = NULL; // the ptr to the array of all node config
int nodenum = 0;

// trigger the main program to reload configuration file
void reload(int sig) {
    doreload = 1;
}
// the subroutine which is used to load configuration from 
// /var/lib/xcat/proxydhcp.cfg to *data
void loadcfg () {
    nodenum = 0;
    free(data);
    data = NULL;
    doreload = 0;

    char *dp = NULL;

    FILE *fp;
    fp = fopen("/var/lib/xcat/proxydhcp.cfg", "r");
    if (fp) {
        int num = chunknum;
        int rtime = 1;
        while (num == chunknum) {
            // realloc the chunknum size of memory each to save memory usage
            data = realloc(data, sizeof(struct nodecfg) * chunknum * rtime);
            if (NULL == data) {
                fprintf (stderr, "Cannot get enough memory.\n");
                free (data);
                return;
            }
            dp = data + sizeof(struct nodecfg) * chunknum * (rtime - 1);
            memset(dp, 0, sizeof(struct nodecfg) * chunknum);
            num = fread(dp, sizeof (struct nodecfg), chunknum, fp);
            nodenum += num;
            rtime++;
        }
        fclose(fp);
    }
}

// get the path of winpe from configuration file which is stored in *data
char *getwinpepath(char *node) {
    int i;
    struct nodecfg *nc = (struct nodecfg *)data;
    for (i=0; i<nodenum;i++) {
        if (0 == strcmp(nc->node, node)) {
            return nc->data;
        }
        nc++;
    }

    return NULL;
}

    
int main(int argc, char *argv[]) {
    int i;
    for(i = 0; i < argc; i++)
    {
        if (strcmp(argv[i], "-V") == 0) {
            verbose = 1;
            setlogmask(LOG_UPTO(LOG_DEBUG));
            openlog("proxydhcp", LOG_NDELAY, LOG_LOCAL0);
        }
    }

    // regist my pid to /var/run/xcat/proxydhcp.pid
    int pid = getpid();
    FILE *pidf = fopen ("/var/run/xcat/proxydhcp.pid", "w");
    if (pidf) {
        fprintf(pidf, "%d", pid);
        fclose (pidf);
    } else {
        fprintf (stderr, "Cannot open /var/run/xcat/proxydhcp.pid\n");
        return 1;
    }

    // load configuration at first start
    loadcfg();

    // regist signal SIGUSR1 for triggering reload configuration from outside
    struct sigaction sigact;
    sigact.sa_handler = &reload;
    sigaction(SIGUSR1, &sigact, NULL);

    int serverfd,port;
    int getpktinfo = 1;
    struct addrinfo hint, *res;
    char cmsg[CMSG_SPACE(sizeof(struct in_pktinfo))];
    char clientpacket[1024];
    struct sockaddr_in clientaddr;
    struct msghdr msg;
    struct cmsghdr *cmsgptr;
    struct iovec iov[1];
    unsigned int myip, clientip;
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

    char defaultwinpe[20] = "Boot/bootmgfw.efi";	
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
        // use select to wait for the 4011 request packages coming
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(serverfd, &fds); 
        struct timeval timeout;
        timeout.tv_sec = 30;
        timeout.tv_usec = 0;
        
        int rc;
        if ((rc = select(serverfd+1,&fds,0,0, &timeout)) <= 0) {
            if (doreload) {
                loadcfg();
                fprintf(stderr, "load in select\n");
            }
            if (verbose) {syslog(LOG_DEBUG, "reload /var/lib/xcat/proxydhcp.cfg\n");}
            continue;
        }
        
        if (doreload) {
            loadcfg();
            if (verbose) {syslog(LOG_DEBUG, "reload /var/lib/xcat/proxydhcp.cfg\n");}
        }
        
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
        
        // get the ip of dhcp client
        clientip = 0;
        int i;
        for (i = 0; i< 4; i++) {
            clientip = clientip << 8;
            clientip += (unsigned char)clientpacket[15-i];
        }
        // get the winpe path
        struct hostent *host = gethostbyaddr(&clientip, sizeof(clientip), AF_INET);
        char *winpepath = defaultwinpe;
        if (host) {
            if (host->h_name) {
                // remove the domain part from hostname
                char *place = strstr(host->h_name, ".");
                if (place) {
                    *place = '\0';
                }
                
                winpepath = getwinpepath(host->h_name);
                if (winpepath == NULL) {
                    winpepath = defaultwinpe;
                }
                if (verbose) {
                    sprintf(logmsg, "Received proxydhcp request from %s\n", host->h_name);
                    syslog(LOG_DEBUG, logmsg); 
                }
            }
        } else {
            winpepath = defaultwinpe;
        }
        
        // get the Vendor class identifier
        char *arch = NULL;
        unsigned char *p = clientpacket + 0xf0;
        while (*p != 0xff && p < (unsigned char *)clientpacket + pktsize) {
            if (*p == 60) {
                arch = p + 0x11;
                break;
            } else {
                p += *(p+1) + 2;
            }
        }
        
        char winboot[50]; // the bootload of winpe
        memset(winboot, 0, 50);
        if (0 == memcmp(arch, "00000", 5)) {  // bios boot mode
            strcpy(winboot, winpepath);
            strcat(winboot, "Boot/pxeboot.0");
        } else if (0 == memcmp(arch, "00007", 5)) {  // uefi boot mode
            strcpy(winboot, winpepath);
            strcat(winboot, "Boot/bootmgfw.efi");
        }

        clientpacket[0] = 2; //change to a reply
        myip = htonl(myip); //endian neutral change
        clientpacket[0x14] = (myip>>24)&0xff; //maybe don't need to do this, maybe assigning the whole int would be better
        clientpacket[0x15] = (myip>>16)&0xff;
        clientpacket[0x16] = (myip>>8)&0xff;
        clientpacket[0x17] = (myip)&0xff;
        txtptr = clientpacket+0x6c;
        strncpy(txtptr, winboot ,128); // keeping 128 in there just in case someone changes the string
        //strncpy(txtptr,"winboot/new/Boot/bootmgfw.efi",128); // keeping 128 in there just in case someone changes the string
        //strncpy(txtptr,"Boot/pxeboot.0",128); // keeping 128 in there just in case someone changes the string
        clientpacket[0xf0]=0x35; //DHCP MSG type 
        clientpacket[0xf1]=0x1; // LEN of 1
        clientpacket[0xf2]=0x5; //DHCP ACK
        clientpacket[0xf3]=0x36; //DHCP server identifier
        clientpacket[0xf4]=0x4; //DHCP server identifier length
        clientpacket[0xf5] = (myip>>24)&0xff; //maybe don't need to do this, maybe assigning the whole int would be better
        clientpacket[0xf6] = (myip>>16)&0xff;
        clientpacket[0xf7] = (myip>>8)&0xff;
        clientpacket[0xf8] = (myip)&0xff;
        
        char winBCD[50];
        strcpy(winBCD, winpepath);
        strcat(winBCD, "Boot/BCD");
        clientpacket[0xf9] = 0xfc; // dhcp 252 'proxy', but coopeted by bootmgfw, it's actually suggesting the boot config file
        clientpacket[0xfa] = strlen(winBCD) + 1; //length of 9
        txtptr = clientpacket+0xfb;
        strncpy(txtptr, winBCD, strlen(winBCD));
        clientpacket[0xfa + strlen(winBCD) + 1] = 0;
        clientpacket[0xfa + strlen(winBCD) + 2] = 0xff;
        sendto(serverfd,clientpacket,pktsize,0,(struct sockaddr*)&clientaddr,sizeof(clientaddr));

        if (verbose) {
            sprintf(logmsg, "Path of bootloader:%s. Path of BCD:%s\n", winboot, winBCD);
            syslog(LOG_DEBUG, logmsg);
        }
    }

    if (verbose) { closelog();}
}


	
	

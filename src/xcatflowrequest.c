/* IBM(c) 2013 EPL licens http://www.eclipse.org/legal/epl-v10.html
 * Jarrod Johnson - jbjohnso@us.ibm.com
 * This program periodically transmits a udp packet to designated xCAT server
 * It waits for an 'ok' and then exits
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char* argv[]) {
	int server;
	struct addrinfo hints;
	struct addrinfo *results,*cur;
	struct timeval timeout;
	int canread=0;
	char buffer[128];
	srand(time(NULL));
	memset(&hints,0,sizeof(struct addrinfo));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_protocol = IPPROTO_UDP;
	fd_set selectset;
	getaddrinfo(argv[1],argv[2],&hints,&results);
	server = socket(AF_UNSPEC,SOCK_DGRAM,17);
	for (cur=results; cur != NULL; cur = cur->ai_next) {
		server = socket(cur->ai_family,cur->ai_socktype,cur->ai_protocol);
		if (server == -1) continue;
		if (connect(server,cur->ai_addr,cur->ai_addrlen) != -1) break;
		close(server);
	}
	FD_ZERO(&selectset);
	FD_SET(server,&selectset);
	while (1) {
		timeout.tv_sec = rand() % 120+60;
		timeout.tv_usec = rand() % 10000;
		write(server,"resourcerequest: xcatd\n",strlen("resourcerequest: xcatd\n"));
		canread = select(FD_SETSIZE,&selectset,NULL,NULL,&timeout);
		if (canread) {
			read(server,buffer,sizeof(buffer));
			if (strncmp(buffer,"resourcerequest: ok",strlen("resourcerequest: ok"))==0) {
				exit(0);
			}
		}
	}
}

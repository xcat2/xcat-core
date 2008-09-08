
#include "winsock2.h"
#include "windows.h"
#include "stdio.h"

void Usage()
{
printf("upflag Ver 0.0.0.1\n");
printf("\nusage:     upflag [hostname][port_number][test_to_send]\n");

printf("\nExamples:");
printf("\nupflag some_hostname 5000 ready");
printf("\nupflag some_hostname 5000 \"I am ready\"");
printf("\nupflag 192.168.0.1 5000 ready\n\n");

}

int SendMsg(SOCKET conn_socket, TCHAR *szMsg)
{
TCHAR szIncomingMsg[255];

szMsg[lstrlen(szMsg)]= '\n\0';

recv(conn_socket, szIncomingMsg, sizeof(szIncomingMsg),0);

printf("\nrecv %s Len: %d ", szIncomingMsg, (int)strlen(szIncomingMsg));

if(strstr(strlwr(szIncomingMsg), "ready") == NULL)
	return 1;

send(conn_socket, (const char *)szMsg, (int)strlen((const char *)szMsg), 0);

lstrcpy(szIncomingMsg, "");
recv(conn_socket, szIncomingMsg, sizeof(szIncomingMsg),0);

printf("\nsend %s Len: %d ", szMsg, strlen((const char *)szMsg));
printf("\nrecv %s Len: %d ", szIncomingMsg, (int)strlen(szIncomingMsg));

if(strstr(strlwr(szIncomingMsg), "done") != NULL)
	return 0;
else
	return 1;

}

int main(int argc, TCHAR* argv[])
{
SOCKET  conn_socket;  
struct hostent *hp;
unsigned int addr;
struct sockaddr_in sa;
WSADATA wsaData;
int iPort;

if((argc < 2) || (lstrcmpi(argv[1] ,"/?") == 0) || (lstrcmpi(argv[1] ,"-?") == 0))
{
	Usage();
	return 1;
}

if(argc == 1)
{
	Usage();
}


if (WSAStartup(0x0101,&wsaData) == SOCKET_ERROR) 
{
	WSACleanup();
	printf("WSAStartup failed with error %d\n",WSAGetLastError());
	return 1;
}

if((hp = gethostbyname((LPCSTR)argv[1])) == NULL)
{
	addr = inet_addr((LPCSTR)argv[1]);
	hp = gethostbyaddr((LPCSTR)&addr,4,AF_INET);
}

memset((LPSTR)&sa,0, sizeof(sa));
memcpy((TCHAR*)&sa.sin_addr, hp->h_addr_list[0] , hp->h_length);

iPort = atoi((LPCSTR)argv[2]);

//sa.sin_addr = hp->h_addr_list[0];
sa.sin_family = PF_INET;
sa.sin_port = htons((u_short)iPort);

conn_socket = socket(AF_INET, SOCK_STREAM, 0);

printf("\nConnecting... ");

int z = connect(conn_socket, (struct sockaddr*)&sa, sizeof(sa));

if(z == SOCKET_ERROR)
{
	z = connect(conn_socket, (struct sockaddr*)&sa, sizeof(sa));

	if(z == SOCKET_ERROR)
	{
		printf("\nUnable to connect to host.");
		printf("\nWSAStartup failed with error %d\n",WSAGetLastError());
		return 1;
	}
	else
	{
		printf("connection was successfull.\n");
	}
}
else
{
	printf("connection was successfull.\n");
}

if(SendMsg(conn_socket, argv[3]) == 0)
{
	WSACleanup();
	return 0;
}
else
{
	WSACleanup();
	return 1;
}

}

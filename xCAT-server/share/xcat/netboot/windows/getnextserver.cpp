/* Another Windows C file.  Build is much like the other, install MS SDK,
 * then run in the 'CMD shell' under SDK folder:
 * cl getnextserver.cpp advapi32.lib
 */
#include <windows.h>
#include <stdio.h>
#include <malloc.h>

int main(int argc, char* argv[]) {
	const char* subkey = "System\\CurrentControlSet\\Control\\PXE";
	HKEY key=0;
	DWORD pxedatasize;
	LPBYTE pxedata;
	DWORD regType;
	if (RegOpenKey(HKEY_LOCAL_MACHINE,subkey,&key) == ERROR_SUCCESS) {
		// Ok, so we have found PXE, we can get next-server, woo
		RegQueryValueEx(key,"BootServerReply",0,&regType,NULL, &pxedatasize);
		pxedata=(LPBYTE)malloc(pxedatasize);
		RegQueryValueEx(key,"BootServerReply",0,&regType,pxedata, &pxedatasize);
		printf("%d.%d.%d.%d\n",pxedata[0x14],pxedata[0x15],pxedata[0x16],pxedata[0x17]);
	}
}


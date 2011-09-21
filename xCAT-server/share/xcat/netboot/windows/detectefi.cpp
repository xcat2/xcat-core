/* Compile this with cl.exe from MS SDK, e.g. 'cl efidetect.cpp', that is all. */
/* IBM(c) 2011 EPL license http://www.eclipse.org/legal/epl-v10.html */

#include <windows.h>
#include <stdio.h>


int main(int argc, char* argv[])
{
	GetFirmwareEnvironmentVariableA("","{00000000-0000-0000-0000-000000000000}",NULL,0);
	if (GetLastError() == ERROR_INVALID_FUNCTION) { // This.. is.. LEGACY BIOOOOOOOOS....
		printf("Legacy");
		return 1;
	} else {
		printf("UEFI");
		return 0;
	}
	return 0;
}

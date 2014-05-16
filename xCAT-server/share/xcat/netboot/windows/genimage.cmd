@echo off
::This script is used to create customized Winpe and BCD for deployment of Windows 8 and Windows Server 2012

::This script requires that the ADK must be installed onto the Windows 
::workstation used to build the winpe and BCD
::'http://www.microsoft.com/en-us/download/details.aspx?id=30652'

::This script can accept three parameters: 
::genimage.cmd arch [winpe name] [bcdonly]

::get the arch from first param
set ARCH=%1%
if [%ARCH%] EQU [x86] set SUFFIX=32
if [%ARCH%] EQU [amd64] set SUFFIX=64
if [%SUFFIX%] EQU [] goto :errorbadargs
::Configuration section
::the drive to use for holding the image
set defdrive=%SystemDrive%

::get the name of winpe
set WINPENAME=
set BCDONLY=
set BOOTPATH=Boot

if [%1] EQU [] goto :errorbadargs
if [%2] EQU [] ( echo Generate winpe to default path %defdrive%\WinPE_%SUFFIX%\media ) else  set WINPENAME=%2%
if [%2] NEQ [] echo Generate winpe to path %defdrive%\WinPE_%SUFFIX%\media\winboot\%WINPENAME%
if [%3] EQU [bcdonly] set BCDONLY=1
if [%WINPENAME%] NEQ [] set BOOTPATH=winboot\%WINPENAME%\Boot

::location where Windows PE from ADK install is located
set adkpedir=%defdrive%\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Windows Preinstallation Environment
set oscdimg=%defdrive%\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg
set WinPERoot=%adkpedir%
set OSCDImgRoot=%oscdimg%
set Path=C:\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\DISM;%Path%

::clean the c:\winPE_amd64 and copy it from ADK
if exist %defdrive%\WinPE_%SUFFIX% rd %defdrive%\WinPE_%SUFFIX% /s /q
set retpath=%cd%
cd /d "%adkpedir%"
call copype.cmd %ARCH% %defdrive%\WinPE_%SUFFIX%
cd /d %retpath%

bcdedit /createstore %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdipath \%BOOTPATH%\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create /d "xCAT WinNB_%SUFFIX%" /application osloader') do set GUID=%%i
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% systemroot \Windows
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% detecthal Yes
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% winpe Yes
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% osdevice ramdisk=[boot]\%BOOTPATH%\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% device ramdisk=[boot]\%BOOTPATH%\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create {bootmgr} /d "xCAT WinNB_%SUFFIX%"
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} timeout 1
bcdedit /store %defdrive%\WinPE_%SUFFiX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} displayorder %GUID%
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
if [%ARCH%] EQU [x86] copy %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %defdrive%\WinPE_%SUFFIX%\media\Boot\B32
if [%ARCH%] EQU [amd64]  copy %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD

::skip the creating of winpe
if [%BCDONLY%] EQU [1] goto :reorgpath

dism /mount-image /imagefile:%defdrive%\WinPE_%SUFFIX%\media\Sources\boot.wim /index:1 /mountdir:%defdrive%\WinPE_%SUFFIX%\mount
cd /d %retpath%
copy startnet.cmd %defdrive%\WinPE_%SUFFIX%\mount\Windows\system32
copy getnextserver.exe %defdrive%\WinPE_%SUFFIX%\mount\Windows\system32
rem copy "%defdrive%\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" %defdrive%\WinPE_%SUFFIX%\mount\Windows\system32
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-WMI.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-Scripting.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-RNDIS.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-NetFX4.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-PowerShell3.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-DismCmdlets.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-StorageWMI.cab"
dism /Image:%defdrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%adkpedir%\amd64\WinPE_OCs\WinPE-WDS-Tools.cab"
copy %defdrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\pxeboot.n12 %defdrive%\WinPE_%SUFFIX%\media\Boot\pxeboot.0
copy %defdrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\wdsmgfw.efi %defdrive%\WinPE_%SUFFIX%\media\Boot\wdsmgfw.efi
copy %defdrive%\WinPE_%SUFFIX%\mount\Windows\Boot\EFI\bootmgfw.efi %defdrive%\WinPE_%SUFFIX%\media\Boot\bootmgfw.efi
copy %defdrive%\WinPE_%SUFFIX%\mount\Windows\Boot\EFI\bootmgr.efi %defdrive%\WinPE_%SUFFIX%\media\Boot\bootmgr.efi
copy %defdrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\bootmgr.exe %defdrive%\WinPE_%SUFFIX%\media\
mkdir %defdrive%\WinPE_%SUFFIX%\media\dvd
copy "%oscdimg%\etfsboot.com" %defdrive%\WinPE_%SUFFIX%\media\dvd
copy "%oscdimg%\efisys_noprompt.bin" %defdrive%\WinPE_%SUFFIX%\media\dvd
rem for /r %defdrive%\drivers %%d in (*.inf) do dism /image:%defdrive%\WinPE_%SUFFIX%\mount /add-driver /driver:%%d 
if exist %defdrive%\drivers dism /image:%defdrive%\WinPE_%SUFFIX%\mount /add-driver /driver:%defdrive%\drivers /recurse
dism /Unmount-Wim /commit /mountdir:%defdrive%\WinPE_%SUFFIX%\mount
move %defdrive%\WinPE_%SUFFIX%\media\Sources\boot.wim %defdrive%\WinPE_%SUFFIX%\media\Boot\WinPE_%SUFFIX%.wim


::move the c:\WinPE_64\media to c:\WinPE_64\media\winboot\<winpe name> if <winpe name> is specified (second param)
:reorgpath
if [%WINPENAME%] NEQ [] rename %defdrive%\WinPE_%SUFFIX%\media origmedia
if [%WINPENAME%] NEQ [] md %defdrive%\WinPE_%SUFFIX%\media\winboot
if [%WINPENAME%] NEQ [] move %defdrive%\WinPE_%SUFFIX%\origmedia %defdrive%\WinPE_%SUFFIX%\media\winboot
if [%WINPENAME%] NEQ [] rename %defdrive%\WinPE_%SUFFIX%\media\winboot\origmedia %WINPENAME%

echo Finished generating of winpe and BCD.
echo "Upload %defdrive%\WinPE_%SUFFIX%\media\* into tftp root directory of xCAT (usually /tftpboot/), should ultimately have /tftpboot/Boot/bootmgfw.efi for example"
goto :eof
:errorbadargs
echo Specify the architecture on the command line
echo Usage: genimage.cmd arch [winpe name] [bcdonly]
echo        e.g. genimage.cmd amd64 mywinpe
echo        e.g. genimage.cmd amd64 bcdonly
goto :eof
:eof

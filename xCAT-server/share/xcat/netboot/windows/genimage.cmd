@echo off
::This script requires that the following be installed onto the Windows 
::workstation used to build the netboot architecture
::'https://www.microsoft.com/downloads/details.aspx?displaylang=en&FamilyID=94bb6e34-d890-4932-81a5-5b50c657de08'
if  [%1] EQU []  goto :errorbadargs
set ARCH=%1%
if [%ARCH%] EQU [x86] set SUFFIX=32
if [%ARCH%] EQU [amd64] set SUFFIX=64
if [%SUFFIX%] EQU [] goto :errorbadargs
::Configuration section
::the drive to use for holding the image
set defdrive=%SystemDrive%
::location where Windows PE from ADK install is located
set adkpedir=%defdrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment
set oscdimg=%defdrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg

if exist %defdrive%\WinPE_%SUFFIX% rd %defdrive%\WinPE_%SUFFIX% /s /q
set retpath=%cd%
cd "%adkpedir%"
call copype.cmd %ARCH% %defdrive%\WinPE_%SUFFIX%
cd /d %retpath%

bcdedit /createstore %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdipath \Boot\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create /d "xCAT WinNB_%SUFFIX%" /application osloader') do set GUID=%%i
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% systemroot \Windows
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% detecthal Yes
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% winpe Yes
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% osdevice ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% device ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create {bootmgr} /d "xCAT WinNB_%SUFFIX%"
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} timeout 1
bcdedit /store %defdrive%\WinPE_%SUFFiX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} displayorder %GUID%
bcdedit /store %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
if [%ARCH%] EQU [x86] copy %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %defdrive%\WinPE_%SUFFIX%\media\Boot\B32
if [%ARCH%] EQU [amd64]  copy %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %defdrive%\WinPE_%SUFFIX%\media\Boot\BCD


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

echo "Upload %defdrive%\WinPE_%SUFFIX%\media\* into tftp root directory of xCAT (usually /tftpboot/), should ultimately have /tftpboot/Boot/bootmgfw.efi for example"
goto :eof
:errorbadargs
echo Specify the architecture on the command line
goto :eof
:eof

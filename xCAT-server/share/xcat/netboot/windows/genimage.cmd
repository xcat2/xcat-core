@echo off
::This script requires that the following be installed onto the Windows 
::workstation used to build the netboot architecture
::'https://www.microsoft.com/downloads/details.aspx?displaylang=en&FamilyID=94bb6e34-d890-4932-81a5-5b50c657de08'
if  [%1] EQU []  goto :errorbadargs
set ARCH=%1%
if [%ARCH%] EQU [x86] set SUFFIX=32
if [%ARCH%] EQU [amd64] set SUFFIX=64
if [%SUFFIX%] EQU [] goto :errorbadargs

if exist %SystemDrive%\WinPE_%SUFFIX% rd %SystemDrive%\WinPE_%SUFFIX% /s /q
cd "%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\"
set retpath=%cd%
call copype.cmd %ARCH% %SystemDrive%\WinPE_%SUFFIX%
cd /d %retpath%

bcdedit /createstore %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdipath \Boot\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create /d "xCAT WinNB_%SUFFIX%" /application osloader') do set GUID=%%i
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% systemroot \Windows
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% detecthal Yes
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% winpe Yes
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% osdevice ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%  /set %GUID% device ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /create {bootmgr} /d "xCAT WinNB_%SUFFIX%"
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} timeout 1
bcdedit /store %SystemDrive%\WinPE_%SUFFiX%\media\Boot\BCD.%SUFFIX% /set {bootmgr} displayorder %GUID%
bcdedit /store %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX%
if [%ARCH%] EQU [x86] copy %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %SystemDrive%\WinPE_%SUFFIX%\media\Boot\B32
if [%ARCH%] EQU [amd64]  copy %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD.%SUFFIX% %SystemDrive%\WinPE_%SUFFIX%\media\Boot\BCD


dism /mount-image /imagefile:%SystemDrive%\WinPE_%SUFFIX%\media\Sources\boot.wim /index:1 /mountdir:%SystemDrive%\WinPE_%SUFFIX%\mount
copy startnet.cmd %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\system32
copy getnextserver.exe %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\system32
rem copy "%SystemDrive%\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\system32
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-Scripting.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-RNDIS.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-NetFX4.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-PowerShell3.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-DismCmdlets.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-StorageWMI.cab"
dism /Image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-package /packagepath:"%SystemDrive%\Program Files (x86)\Windows Kits\8.0\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WDS-Tools.cab"
copy %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\pxeboot.n12 %SystemDrive%\WinPE_%SUFFIX%\media\Boot\pxeboot.0
copy %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\wdsmgfw.efi %SystemDrive%\WinPE_%SUFFIX%\media\Boot\wdsmgfw.efi
copy %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\Boot\EFI\bootmgfw.efi %SystemDrive%\WinPE_%SUFFIX%\media\Boot\bootmgfw.efi
copy %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\Boot\EFI\bootmgr.efi %SystemDrive%\WinPE_%SUFFIX%\media\Boot\bootmgr.efi
copy %SystemDrive%\WinPE_%SUFFIX%\mount\Windows\Boot\PXE\bootmgr.exe %SystemDrive%\WinPE_%SUFFIX%\media\
rem for /r %SystemDrive%\drivers %%d in (*.inf) do dism /image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-driver /driver:%%d 
if exist %SystemDrive%\drivers dism /image:%SystemDrive%\WinPE_%SUFFIX%\mount /add-driver /driver:%SystemDrive%\drivers /recurse
dism /Unmount-Wim /commit /mountdir:%SystemDrive%\WinPE_%SUFFIX%\mount
move %SystemDrive%\WinPE_%SUFFIX%\media\Sources\boot.wim %SystemDrive%\WinPE_%SUFFIX%\media\Boot\WinPE_%SUFFIX%.wim

echo "Upload %SystemDrive%\WinPE_%SUFFIX%\media\* into tftp root directory of xCAT (usually /tftpboot/), should ultimately have /tftpboot/Boot/bootmgfw.efi for example"
goto :eof
:errorbadargs
echo Specify the architecture on the command line
goto :eof
:eof

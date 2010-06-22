@echo off
::This script requires that the following be installed onto the Windows 
::workstation used to build the netboot architecture
::'https://www.microsoft.com/downloads/details.aspx?displaylang=en&FamilyID=94bb6e34-d890-4932-81a5-5b50c657de08'
if  [%1] EQU []  goto :errorbadargs
set ARCH=%1%
if [%ARCH%] EQU [x86] set SUFFIX=32
if [%ARCH%] EQU [amd64] set SUFFIX=64
if [%SUFFIX%] EQU [] goto :errorbadargs

if exist c:\WinPE_%SUFFIX% rd c:\WinPE_%SUFFIX% /s /q
md c:\WinPE_%SUFFIX%
md c:\WinPE_%SUFFIX%\rootfs
md c:\WinPE_%SUFFIX%\pxe
md c:\WinPE_%SUFFIX%\pxe\Boot\
md c:\WinPE_%SUFFIX%\pxe\Boot\Fonts
if exist "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\bootmgr" copy "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\boot\fonts\wgl4_boot.ttf" "c:\WinPE_%SUFFIX%\pxe\Boot\Fonts"
if exist "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\Boot\boot.sdi" copy "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\boot\boot.sdi" "c:\WinPE_%SUFFIX%\pxe\Boot\boot.sdi"
copy "c:\Program Files\Windows AIK\Tools\PETools\%ARCH%\winpe.wim" "c:\WinPE_%SUFFIX%\pxe\Boot\WinPE_%SUFFIX%.wim"

bcdedit /createstore c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdipath \Boot\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX% /create /d "xCAT WinNB_%SUFFIX%" /application osloader') do set GUID=%%i
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set %GUID% systemroot \Windows
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set %GUID% detecthal Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set %GUID% winpe Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set %GUID% osdevice ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%  /set %GUID% device ramdisk=[boot]\Boot\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX% /create {bootmgr} /d "xCAT WinNB_%SUFFIX%"
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX% /set {bootmgr} timeout 1
bcdedit /store c:\WinPE_%SUFFiX%\pxe\Boot\BCD.%SUFFIX% /set {bootmgr} displayorder %GUID%
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX%
if [%ARCH%] EQU [x86] copy c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX% c:\WinPE_%SUFFIX%\pxe\Boot\B32
if [%ARCH%] EQU [amd64]  copy c:\WinPE_%SUFFIX%\pxe\Boot\BCD.%SUFFIX% c:\WinPE_%SUFFIX%\pxe\Boot\BCD


dism /mount-wim /wimfile:c:\WinPE_%SUFFIX%\pxe\Boot\winpe_%SUFFIX%.wim /index:1 /mountdir:c:\WinPE_%SUFFIX%\rootfs
copy startnet.cmd c:\WinPE_%SUFFIX%\rootfs\Windows\system32
copy "C:\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" c:\WinPE_%SUFFIX%\rootfs\Windows\system32
dism /Image:c:\WinPE_%SUFFIX%\rootfs /add-package /packagepath:"C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\WinPE_FPs\winpe-wmi.cab"
dism /Image:c:\WinPE_%SUFFIX%\rootfs /add-package /packagepath:"C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\WinPE_FPs\winpe-scripting.cab"
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\pxeboot.n12 c:\WinPE_%SUFFIX%\pxe\Boot\pxeboot.0
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\wdsmgfw.efi c:\WinPE_%SUFFIX%\pxe\Boot\wdsmgfw.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\EFI\bootmgfw.efi c:\WinPE_%SUFFIX%\pxe\Boot\bootmgfw.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\EFI\bootmgr.efi c:\WinPE_%SUFFIX%\pxe\Boot\bootmgr.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\bootmgr.exe c:\WinPE_%SUFFIX%\pxe\
for /r c:\drivers %%d in (*.inf) do dism /image c:\WinPE_%SUFFIX%\rootfs /add-driver /driver:%%d 
dism /Unmount-Wim /commit /mountdir:c:\WinPE_%SUFFIX%\rootfs

echo Upload c:\WinPE_%SUFFIX%\pxe to somewhere
goto :eof
:errorbadargs
echo Specify the architecture on the command line
goto :eof
:eof

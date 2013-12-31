@echo off

::This script is used to create customized Winpe and BCD for deployment of Windows 7 and Windows Server 2008

::This script requires that the AIK must be installed onto the Windows 
::workstation used to build the winpe and BCD
::AIK download path
::'https://www.microsoft.com/downloads/details.aspx?displaylang=en&FamilyID=94bb6e34-d890-4932-81a5-5b50c657de08'

::This script can accept three parameters: 
::genimage.bat arch [winpe name] [bcd create only]

set ROOTPATH=
set BCDONLY=
set BOOTPATH=Boot

if [%1] EQU []  goto :errorbadargs
::if [%2] EQU [] ( echo Default path ) else ( set ROOTPATH=winboot\%2%; set BOOTPATH=winboot\%2%\Boot)
if [%2] EQU [] ( echo Generate winpe to default path c:\WinPE_%SUFFIX%\pxe ) else  set ROOTPATH=winboot\%2% 
if [%2] NEQ [] set BOOTPATH=winboot\%2%\Boot
if [%2] NEQ [] echo Generate winpe to path c:\WinPE_%SUFFIX%\pxe\%ROOTPATH%
if [%3] EQU [bcdonly] set BCDONLY=1

::get the arch from first param
set ARCH=%1%
if [%ARCH%] EQU [x86] set SUFFIX=32
if [%ARCH%] EQU [amd64] set SUFFIX=64
if [%SUFFIX%] EQU [] goto :errorbadargs

if exist c:\WinPE_%SUFFIX% rd c:\WinPE_%SUFFIX% /s /q
md c:\WinPE_%SUFFIX%
md c:\WinPE_%SUFFIX%\rootfs
md c:\WinPE_%SUFFIX%\pxe
md c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\
md c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\Fonts

bcdedit /createstore c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set {ramdiskoptions} ramdisksdipath \%BOOTPATH%\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX% /create /d "xCAT WinNB_%SUFFIX%" /application osloader') do set GUID=%%i
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set %GUID% systemroot \Windows
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set %GUID% detecthal Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set %GUID% winpe Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set %GUID% osdevice ramdisk=[boot]\%BOOTPATH%\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store C:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%  /set %GUID% device ramdisk=[boot]\%BOOTPATH%\WinPE_%SUFFIX%.wim,{ramdiskoptions}
bcdedit /store c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX% /create {bootmgr} /d "xCAT WinNB_%SUFFIX%"
bcdedit /store c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX% /set {bootmgr} timeout 1
bcdedit /store c:\WinPE_%SUFFiX%\pxe\%BOOTPATH%\BCD.%SUFFIX% /set {bootmgr} displayorder %GUID%
bcdedit /store c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX%
if [%ARCH%] EQU [x86] copy c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX% c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\B32
if [%ARCH%] EQU [amd64]  copy c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD.%SUFFIX% c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\BCD

if [%BCDONLY%] EQU [1] goto :eof

if exist "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\bootmgr" copy "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\boot\fonts\wgl4_boot.ttf" "c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\Fonts"
if exist "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\Boot\boot.sdi" copy "C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\boot\boot.sdi" "c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\boot.sdi"
copy "c:\Program Files\Windows AIK\Tools\PETools\%ARCH%\winpe.wim" "c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\WinPE_%SUFFIX%.wim"

dism /mount-wim /wimfile:c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\winpe_%SUFFIX%.wim /index:1 /mountdir:c:\WinPE_%SUFFIX%\rootfs
copy startnet.cmd c:\WinPE_%SUFFIX%\rootfs\Windows\system32
copy getnextserver.exe c:\WinPE_%SUFFIX%\rootfs\Windows\system32
copy "C:\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" c:\WinPE_%SUFFIX%\rootfs\Windows\system32
dism /Image:c:\WinPE_%SUFFIX%\rootfs /add-package /packagepath:"C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\WinPE_FPs\winpe-wmi.cab"
dism /Image:c:\WinPE_%SUFFIX%\rootfs /add-package /packagepath:"C:\Program Files\Windows AIK\Tools\PETools\%ARCH%\WinPE_FPs\winpe-scripting.cab"
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\pxeboot.n12 c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\pxeboot.0
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\wdsmgfw.efi c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\wdsmgfw.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\EFI\bootmgfw.efi c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\bootmgfw.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\EFI\bootmgr.efi c:\WinPE_%SUFFIX%\pxe\%BOOTPATH%\bootmgr.efi
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\bootmgr.exe c:\WinPE_%SUFFIX%\pxe\%ROOTPATH%
for /r c:\drivers %%d in (*.inf) do dism /image:c:\WinPE_%SUFFIX%\rootfs /add-driver /driver:%%d /forceunsigned

dism /Unmount-Wim /commit /mountdir:c:\WinPE_%SUFFIX%\rootfs

echo Finished generating of winpe and BCD.
echo Copy c:\WinPE_%SUFFIX%\pxe\* to xCAT MN:/tftpboot.
goto :eof
:errorbadargs
echo Specify the architecture on the command line
echo Usage: genimage.bat arch [winpe name] [bcd create only]
goto :eof
:eof

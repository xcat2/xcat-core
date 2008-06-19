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
copy "c:\Program Files\Windows AIK\Tools\PETools\%ARCH%\winpe.wim" "c:\WinPE_%SUFFIX%\pxe\Boot\WinPE.wim"

bcdedit /createstore c:\WinPE_%SUFFIX%\pxe\Boot\BCD
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /create {ramdiskoptions} /d "Ramdisk options"
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set {ramdiskoptions} ramdisksdipath \Boot\boot.sdi
for /f "Tokens=3" %%i in ('bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD /create /d "xCAT WinNB" /application osloader') do set GUID=%%i
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set %GUID% systemroot \Windows
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set %GUID% detecthal Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set %GUID% winpe Yes
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set %GUID% osdevice ramdisk=[boot]\Boot\WinPE.wim,{ramdiskoptions}
bcdedit /store C:\WinPE_%SUFFIX%\pxe\Boot\BCD  /set %GUID% device ramdisk=[boot]\Boot\WinPE.wim,{ramdiskoptions}
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD /create {bootmgr} /d "xCAT WinNB"
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD /set {bootmgr} timeout 1
bcdedit /store c:\WinPE_%SUFFiX%\pxe\Boot\BCD /set {bootmgr} displayorder %GUID%
bcdedit /store c:\WinPE_%SUFFIX%\pxe\Boot\BCD

"C:\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" /mountrw c:\WinPE_%SUFFIX%\pxe\Boot\winpe.wim 1 c:\WinPE_%SUFFIX%\rootfs
copy startnet.cmd c:\WinPE_%SUFFIX%\rootfs\Windows\system32
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\pxeboot.n12 c:\WinPE_%SUFFIX%\pxe\Boot\pxeboot.0
copy c:\WinPE_%SUFFIX%\rootfs\Windows\Boot\PXE\bootmgr.exe c:\WinPE_%SUFFIX%\pxe\
for /r c:\drivers %%d in (*.inf) do "C:\Program Files\Windows AIK\Tools\PETools\peimg.exe" /inf=%%d c:\WinPE_%SUFFIX%\rootfs
"C:\Program Files\Windows AIK\Tools\PETools\peimg.exe" /inf= c:\WinPE_%SUFFIX%\rootfs
"C:\Program Files\Windows AIK\Tools\%ARCH%\imagex.exe" /unmount /commit c:\WinPE_%SUFFIX%\rootfs

echo Upload c:\WinPE_%SUFFIX%\pxe to somewhere
goto :eof
:errorbadargs
echo Specify the architecture on the command line
goto :eof
:eof

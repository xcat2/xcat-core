@echo off
start /min cmd
echo Initializing, please wait.
FOR /F "tokens=*" %%A IN ('wmic csproduct get uuid /Format:list ^| FIND "="') DO SET %%A
echo REGEDIT4 >> duiduuid.reg
echo. >> duiduuid.reg
echo [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\TCPIP6\Parameters] >> duiduuid.reg
echo "Dhcpv6DUID"=hex:00,04,%uuid:~0,2%,%uuid:~2,2%,%uuid:~4,2%,%uuid:~6,2%,%uuid:~9,2%,%uuid:~11,2%,%uuid:~14,2%,%uuid:~16,2%,%uuid:~19,2%,%uuid:~21,2%,%uuid:~24,2%,%uuid:~26,2%,%uuid:~28,2%,%uuid:~30,2%,%uuid:~32,2%,%uuid:~34,2% >> duiduuid.reg
echo. >> duiduuid.reg
regedit /s duiduuid.reg
for /f "delims=" %%a in ('wmic cdrom get drive ^| find ":"') do set optdrive=%%a
if not defined optdrive GOTO :netboot
set optdrive=%optdrive: =%
if not exist %optdrive%\dvdboot.cmd GOTO :netboot
call %optdrive%\dvdboot.cmd
goto :end
:netboot
wpeinit
for /f %%A IN ('getnextserver.exe') DO SET XCATD=%%A
echo Waiting for xCAT server %XCATD% to become reachable (check WinPE network drivers if this does not proceeed)
:noping
ping -n 1 %XCATD% 2> NUL | find "TTL=" > NUL || goto :noping
md \xcat
echo Waiting for successful mount of \\%XCATD%\install (if this hangs, check that samba is running)
:nomount
net use i: \\%XCATD%\install || goto :nomount
echo Successfully mounted \\%XCATD%\install, moving on to execute remote script
for /f "delims=: tokens=2" %%c in ('ipconfig ^|find "IPv4 Address. . ."') do for /f "tokens=1" %%d in ('echo %%c') do for /f "delims=. tokens=1,2,3,4" %%m in ('echo %%d') do if "%%m.%%n" NEQ  "169.254" set NODEIP=%%m.%%n.%%o.%%p
for /f %%c in ('echo %NODEIP%') do set NODEIP=%%c
if exist  i:\autoinst\%NODEIP%.cmd copy i:\autoinst\%NODEIP%.cmd x:\xcat\autoscript.cmd
if exist i:\autoinst\%uuid%.cmd copy i:\autoinst\%uuid%.cmd x:\xcat\autoscript.cmd
if not exist x:\xcat\autoscript.cmd echo I could not find my autoinst file
if not exist x:\xcat\autoscript.cmd pause
call x:\xcat\autoscript.cmd
wpeutil reboot
:end

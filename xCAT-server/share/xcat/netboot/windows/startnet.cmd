@echo off
echo Initializing, please wait.
FOR /F "tokens=*" %%A IN ('wmic csproduct get uuid /Format:list ^| FIND "="') DO SET %%A
set guid=%uuid:~6,2%%uuid:~4,2%%uuid:~2,2%%uuid:~0,2%-%uuid:~11,2%%uuid:~9,2%-%uuid:~16,2%%uuid:~14,2%%uuid:~18,18%
echo REGEDIT4 >> duiduuid.reg
echo. >> duiduuid.reg
echo [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\TCPIP6\Parameters] >> duiduuid.reg
echo "Dhcpv6DUID"=hex:00,04,%guid:~0,2%,%guid:~2,2%,%guid:~4,2%,%guid:~6,2%,%guid:~9,2%,%guid:~11,2%,%guid:~14,2%,%guid:~16,2%,%guid:~19,2%,%guid:~21,2%,%guid:~24,2%,%guid:~26,2%,%guid:~28,2%,%guid:~30,2%,%guid:~32,2%,%guid:~34,2% >> duiduuid.reg
echo. >> duiduuid.reg
regedit /s duiduuid.reg
wpeinit
start /min cmd
for /f %%A IN ('getnextserver.exe') DO SET XCATD=%%A
echo Waiting for xCAT server %XCATD% to become reachable (check WinPE network drivers if this does not proceeed)
:noping
ping -n 1 %XCATD% 2> NUL | find "TTL=" > NUL || goto :noping
md \xcat
echo Waiting for successful mount of \\%XCATD%\install (if this hangs, check that samba is running)
:nomount
net use i: \\%XCATD%\install || goto :nomount
echo Successfully mounted \\%XCATD%\install, moving on to execute remote script
for /f "delims=: tokens=2" %%c in ('ipconfig ^|find "IPv4 Address. . ."') do set NODEIP=%%c
for /f %%c in ('echo %NODEIP%') do set NODEIP=%%c
if exist  i:\autoinst\%NODEIP%.cmd copy i:\autoinst\%NODEIP%.cmd x:\xcat\autoscript.cmd
if exist i:\autoinst\%guid%.cmd copy i:\autoinst\%guid%.cmd x:\xcat\autoscript.cmd
call x:\xcat\autoscript.cmd
wpeutil reboot

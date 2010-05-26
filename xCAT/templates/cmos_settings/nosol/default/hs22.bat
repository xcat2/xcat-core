loaddefault uEFI
loaddefault BootOrder
set BootOrder.BootOrder "Legacy Only=PXE Network=Hard Disk 0"
set uEFI.RemoteConsoleRedirection Enable
set uEFI.Com2TextEmul VT100
set uEFI.Com2ActiveAfterBoot Enable
set uEFI.Com2FlowControl Hardware
set uEFI.LegacyOptionRomPort "COM Port 1"

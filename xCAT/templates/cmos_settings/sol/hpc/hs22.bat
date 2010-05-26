loaddefault uEFI
loaddefault BootOrder
set BootOrder.BootOrder "Legacy Only=PXE Network=Hard Disk 0"
set uEFI.RemoteConsoleRedirection Enable
set uEFI.Com2TextEmul VT100
set uEFI.Com2ActiveAfterBoot Enable
set uEFI.Com2FlowControl Hardware
set uEFI.ProcessorHyperThreading Disable
set uEFI.OperatingMode "Custom Mode"
set uEFI.ProcessorEistEnable "Enable"
set uEFI.ProcessorC1eEnable "Disable"
set uEFI.TurboModeEnable "Enable"
set uEFI.PackageCState "ACPI C3"
set uEFI.QPISpeed "Max Performance"


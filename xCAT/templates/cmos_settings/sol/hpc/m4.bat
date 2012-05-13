loaddefault uEFI
loaddefault BootOrder
set BootOrder.BootOrder "PXE Network=Hard Disk 0"
set Processors.Hyper-Threading "Disable"
set DevicesandIOPorts.RemoteConsole "Enable"
set DevicesandIOPorts.SerialPortSharing "Enable"
set DevicesandIOPorts.SerialPortAccessMode "Dedicated"
set DevicesandIOPorts.Com1TerminalEmulation "VT100"
set DevicesandIOPorts.Com1ActiveAfterBoot "Enable"
set OperatingModes.ChooseOperatingMode "Custom Mode"
set Processors.C1EnhancedMode "Disable"
set Processors.TurboMode "Enable"
set Processors.PackageACPIC-StateLimit "ACPI C3"
set Processors.QPILinkFrequency "Max Performance"

# IBM(c) 2008 EPL license http://www.eclipse.org/legal/epl-v10.html
# Ver. 2.1 (3) - sf@mauricebrinkmann.de
#-------------------------------------------------------

package xCAT::vboxService;
my %methods = (
IVirtualBox_getExtraData => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getExtraData
ISerialPort_setHostMode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hostMode', type => 'vbox:PortMode', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setHostMode
IHostFloppyDrive_getName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostFloppyDrive_getName
IVHDImage_getCreated => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVHDImage_getCreated
IFloppyDrive_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_setEnabled
IUSBDeviceFilter_getManufacturer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getManufacturer
IParallelPort_setIOBase => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'IOBase', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IParallelPort_setIOBase
ISystemProperties_getNetworkAdapterCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getNetworkAdapterCount
IMachine_getName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getName
IVRDPServer_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setEnabled
IHardDisk_setDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'description', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_setDescription
IVRDPServer_getNetAddress => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getNetAddress
ISnapshot_getChildren => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getChildren
IMachine_getOSTypeId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getOSTypeId
IUSBDevice_getRevision => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getRevision
IVirtualDiskImage_deleteImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_deleteImage
IHardDisk_setType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'type', type => 'vbox:HardDiskType', attr => {}),
    ], # end parameters
  }, # end IHardDisk_setType
IVirtualBox_getHost => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getHost
IMachine_setCurrentSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setCurrentSnapshot
IUSBDevice_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getId
IDVDDrive_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_getState
IISCSIHardDisk_getLun => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getLun
IConsole_getSharedFolders => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getSharedFolders
IMachine_getVRAMSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getVRAMSize
IMachine_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getId
ISerialPort_setServer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'server', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setServer
ISnapshot_setName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_setName
IMachine_getPAEEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getPAEEnabled
IVirtualBox_getDVDImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getDVDImage
IUSBDevice_getProductId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getProductId
ISnapshot_getTimeStamp => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getTimeStamp
IVirtualBox_openFloppyImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openFloppyImage
IHost_getFloppyDrives => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getFloppyDrives
IMachine_getLogFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getLogFolder
IMachine_getBIOSSettings => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getBIOSSettings
ISystemProperties_getMinGuestVRAM => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMinGuestVRAM
IVirtualBox_registerFloppyImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'image', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_registerFloppyImage
IHardDisk_getStorageType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getStorageType
INetworkAdapter_attachToInternalNetwork => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_attachToInternalNetwork
ISerialPort_getPath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getPath
ISATAController_getPortCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISATAController_getPortCount
IHardDisk_getLocation => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getLocation
IProgress_getResultCode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getResultCode
ISystemProperties_getMaxBootPosition => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMaxBootPosition
IMachine_getStateFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getStateFilePath
IUSBController_getDeviceFilters => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_getDeviceFilters
IVirtualBox_saveSettingsWithBackup => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_saveSettingsWithBackup
IMachine_attachHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'bus', type => 'vbox:StorageBus', attr => {}),
      SOAP::Data->new(name => 'channel', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'device', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IMachine_attachHardDisk
IMachine_getSettingsFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSettingsFilePath
INetworkAdapter_setLineSpeed => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'lineSpeed', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setLineSpeed
IConsole_pause => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_pause
IMachine_getClipboardMode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getClipboardMode
IVirtualBox_getMachines2 => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getMachines2
ISerialPort_setIOBase => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'IOBase', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setIOBase
IMachine_setName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setName
IMachine_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getState
ISerialPort_getSlot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getSlot
INetworkAdapter_setAdapterType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'adapterType', type => 'vbox:NetworkAdapterType', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setAdapterType
IConsole_takeSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'description', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_takeSnapshot
IVirtualDiskImage_createFixedImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_createFixedImage
IMachine_getCurrentSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getCurrentSnapshot
IConsole_getRemoteUSBDevices => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getRemoteUSBDevices
IVirtualBox_getFloppyImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getFloppyImage
INetworkAdapter_setTraceEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'traceEnabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setTraceEnabled
IProgress_getCompleted => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getCompleted
IISCSIHardDisk_setUserName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'userName', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setUserName
ISystemProperties_getMaxVDISize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMaxVDISize
IConsole_getUSBDevices => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getUSBDevices
IVRDPServer_getAuthType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getAuthType
IMachine_discardSettings => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_discardSettings
IHost_getUSBDeviceFilters => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getUSBDeviceFilters
IParallelPort_setPath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'path', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_setPath
IParallelPort_setIRQ => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'IRQ', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IParallelPort_setIRQ
IMouse_getAbsoluteSupported => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMouse_getAbsoluteSupported
IUSBDeviceFilter_setRevision => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'revision', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setRevision
IFloppyDrive_getHostDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_getHostDrive
IMachine_getSerialPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'slot', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_getSerialPort
IMachine_detachHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'bus', type => 'vbox:StorageBus', attr => {}),
      SOAP::Data->new(name => 'channel', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'device', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IMachine_detachHardDisk
IHardDisk_getRoot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getRoot
INetworkAdapter_detach => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_detach
ISession_getMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISession_getMachine
IMachine_getStatisticsUpdateInterval => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getStatisticsUpdateInterval
ISerialPort_setPath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'path', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setPath
IKeyboard_putCAD => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IKeyboard_putCAD
IMachine_getParallelPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'slot', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_getParallelPort
ICustomHardDisk_setLocation => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'location', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_setLocation
IMachine_getMemoryBalloonSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getMemoryBalloonSize
IUSBDeviceFilter_setManufacturer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'manufacturer', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setManufacturer
IVHDImage_deleteImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVHDImage_deleteImage
IFloppyDrive_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_getState
IUSBController_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IUSBController_setEnabled
IMachine_getSnapshotCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSnapshotCount
IVRDPServer_getAllowMultiConnection => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getAllowMultiConnection
IVirtualBox_getGuestOSTypes => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getGuestOSTypes
IMachine_createSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hostPath', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'writable', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IMachine_createSharedFolder
IVirtualBox_registerHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hardDisk', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_registerHardDisk
ISession_close => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISession_close
IVRDPServer_setAuthType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'authType', type => 'vbox:VRDPAuthType', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setAuthType
ISerialPort_setIRQ => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'IRQ', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setIRQ
IMachine_getNetworkAdapter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'slot', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_getNetworkAdapter
IMachine_getSessionType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSessionType
IVMDKImage_deleteImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_deleteImage
IHost_createUSBDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_createUSBDeviceFilter
IVirtualBox_createHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'storageType', type => 'vbox:HardDiskStorageType', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_createHardDisk
IHardDisk_getLastAccessError => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getLastAccessError
ISATAController_setPortCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'portCount', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end ISATAController_setPortCount
IISCSIHardDisk_setPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'port', type => 'xsd:unsignedShort', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setPort
IVirtualDiskImage_getCreated => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_getCreated
IVirtualBox_unregisterHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_unregisterHardDisk
IFloppyDrive_mountImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'imageId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_mountImage
INetworkAdapter_getLineSpeed => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getLineSpeed
IConsole_getMouse => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getMouse
INetworkAdapter_getCableConnected => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getCableConnected
IVirtualBox_setExtraData => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'value', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_setExtraData
IVirtualBox_getSystemProperties => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getSystemProperties
IUSBController_getUSBStandard => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_getUSBStandard
IMachine_setPAEEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'PAEEnabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IMachine_setPAEEnabled
IFloppyImage_getAccessible => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyImage_getAccessible
IProgress_getOperation => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getOperation
IVirtualBox_getSettingsFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getSettingsFilePath
IHardDisk_getType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getType
IMachine_showConsoleWindow => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_showConsoleWindow
IConsole_detachUSBDevice => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_detachUSBDevice
IMachine_getSATAController => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSATAController
IUSBController_insertDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'position', type => 'xsd:unsignedInt', attr => {}),
      SOAP::Data->new(name => 'filter', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_insertDeviceFilter
ISession_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISession_getState
IVirtualBox_unregisterDVDImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_unregisterDVDImage
ISystemProperties_getDefaultVDIFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getDefaultVDIFolder
IHost_getOperatingSystem => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getOperatingSystem
IHostDVDDrive_getName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostDVDDrive_getName
IMachine_getHWVirtExEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getHWVirtExEnabled
IMachine_setMemoryBalloonSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'memoryBalloonSize', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_setMemoryBalloonSize
IMachine_getLastStateChange => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getLastStateChange
IConsole_powerDown => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_powerDown
IAudioAdapter_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_getEnabled
IMachine_setMemorySize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'memorySize', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_setMemorySize
IUSBDevice_getAddress => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getAddress
IConsole_getKeyboard => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getKeyboard
INetworkAdapter_setTraceFile => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'traceFile', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setTraceFile
IProgress_getCancelable => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getCancelable
IConsole_reset => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_reset
IVirtualBox_registerDVDImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'image', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_registerDVDImage
IISCSIHardDisk_setServer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'server', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setServer
IProgress_getCanceled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getCanceled
ISystemProperties_getParallelPortCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getParallelPortCount
INetworkAdapter_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getEnabled
IDVDImage_getSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDImage_getSize
IMachine_getSessionState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSessionState
ISession_getConsole => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISession_getConsole
INetworkAdapter_getAttachmentType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getAttachmentType
IMouse_putMouseEventAbsolute => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'x', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'y', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'dz', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'buttonState', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IMouse_putMouseEventAbsolute
IWebsessionManager_logon => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => 'username', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'password', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IWebsessionManager_logon
IParallelPort_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_getEnabled
INetworkAdapter_attachToHostInterface => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_attachToHostInterface
IParallelPort_getIRQ => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_getIRQ
IVirtualBox_openHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'location', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openHardDisk
IUSBDeviceFilter_getName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getName
IConsole_resume => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_resume
IFloppyImage_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyImage_getId
IVHDImage_setFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVHDImage_setFilePath
IHost_getDVDDrives => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getDVDDrives
IVirtualBox_registerMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'machine', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_registerMachine
IManagedObjectRef_release => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IManagedObjectRef_release
INetworkAdapter_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setEnabled
IMachine_setHWVirtExEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'HWVirtExEnabled', type => 'vbox:TSBool', attr => {}),
    ], # end parameters
  }, # end IMachine_setHWVirtExEnabled
IParallelPort_getIOBase => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_getIOBase
IISCSIHardDisk_getServer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getServer
IConsole_adoptSavedState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'savedStateFile', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_adoptSavedState
IMachine_saveSettingsWithBackup => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_saveSettingsWithBackup
IVRDPServer_setAuthTimeout => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'authTimeout', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setAuthTimeout
IMachine_getHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'bus', type => 'vbox:StorageBus', attr => {}),
      SOAP::Data->new(name => 'channel', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'device', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IMachine_getHardDisk
IVRDPServer_getAuthTimeout => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getAuthTimeout
IISCSIHardDisk_setTarget => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'target', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setTarget
IFloppyDrive_unmount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_unmount
IMachine_getFloppyDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getFloppyDrive
ISnapshot_setDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'description', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_setDescription
IUSBDeviceFilter_setProductId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'productId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setProductId
IUSBDevice_getPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getPort
IProgress_getOperationDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getOperationDescription
IVRDPServer_setNetAddress => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'netAddress', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setNetAddress
IDVDDrive_setPassthrough => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'passthrough', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_setPassthrough
IUSBDevice_getProduct => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getProduct
ISystemProperties_getMaxGuestRAM => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMaxGuestRAM
IHost_removeUSBDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'position', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IHost_removeUSBDeviceFilter
IMachine_getHardDiskAttachments => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getHardDiskAttachments
IMachine_getSnapshotFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSnapshotFolder
IVirtualDiskImage_getFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_getFilePath
IConsole_discardCurrentState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_discardCurrentState
IFloppyDrive_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_getEnabled
IConsole_sleepButton => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_sleepButton
IMouse_putMouseEvent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'dx', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'dy', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'dz', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'buttonState', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IMouse_putMouseEvent
IUSBDeviceFilter_setActive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'active', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setActive
IVirtualBox_openMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'settingsFile', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openMachine
IConsole_discardSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_discardSnapshot
ISystemProperties_setLogHistoryCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'LogHistoryCount', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setLogHistoryCount
IHost_getUSBDevices => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getUSBDevices
IVirtualBox_unregisterFloppyImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_unregisterFloppyImage
IISCSIHardDisk_getUserName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getUserName
IHost_insertUSBDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'position', type => 'xsd:unsignedInt', attr => {}),
      SOAP::Data->new(name => 'filter', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_insertUSBDeviceFilter
IMachine_canShowConsoleWindow => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_canShowConsoleWindow
IUSBDeviceFilter_getProduct => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getProduct
ISnapshot_getMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getMachine
IParallelPort_getSlot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_getSlot
IConsole_discardSavedState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_discardSavedState
IMachine_saveSettings => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_saveSettings
ICustomHardDisk_deleteImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_deleteImage
ISerialPort_getIRQ => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getIRQ
IHardDisk_getChildren => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getChildren
IDVDDrive_captureHostDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'drive', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_captureHostDrive
IConsole_createSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hostPath', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'writable', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IConsole_createSharedFolder
IHardDisk_getMachineId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getMachineId
IMachine_getVRDPServer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getVRDPServer
IConsole_removeSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_removeSharedFolder
IVMDKImage_getFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_getFilePath
IMachine_getSettingsFileVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSettingsFileVersion
IVirtualBox_createLegacyMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'settingsFile', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_createLegacyMachine
IVirtualBox_findVirtualDiskImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_findVirtualDiskImage
IVirtualBox_getFloppyImageUsage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'usage', type => 'vbox:ResourceUsage', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getFloppyImageUsage
IVirtualDiskImage_setFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_setFilePath
IUSBDeviceFilter_getRemote => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getRemote
INetworkAdapter_setMACAddress => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'MACAddress', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setMACAddress
ISystemProperties_getRemoteDisplayAuthLibrary => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getRemoteDisplayAuthLibrary
INetworkAdapter_setInternalNetwork => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'internalNetwork', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setInternalNetwork
IHardDisk_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getId
IDVDDrive_getImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_getImage
ICustomHardDisk_getFormat => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_getFormat
ISystemProperties_getSerialPortCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getSerialPortCount
ISATAController_GetIDEEmulationPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'devicePosition', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end ISATAController_GetIDEEmulationPort
INetworkAdapter_getTraceFile => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getTraceFile
ISystemProperties_getDefaultMachineFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getDefaultMachineFolder
IISCSIHardDisk_setLun => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'lun', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setLun
IFloppyImage_getFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyImage_getFilePath
INetworkAdapter_getNATNetwork => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getNATNetwork
ISnapshot_getOnline => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getOnline
IVRDPServer_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getEnabled
IManagedObjectRef_getInterfaceName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IManagedObjectRef_getInterfaceName
ICustomHardDisk_createFixedImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_createFixedImage
ISnapshot_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getId
IConsole_getRemoteDisplayInfo => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getRemoteDisplayInfo
IISCSIHardDisk_setPassword => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'password', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_setPassword
IHardDisk_getActualSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getActualSize
IVirtualBox_removeSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_removeSharedFolder
IConsole_attachUSBDevice => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_attachUSBDevice
IISCSIHardDisk_getPassword => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getPassword
IVirtualBox_getGuestOSType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getGuestOSType
ISnapshot_getName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getName
IHardDisk_getAccessible => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getAccessible
IParallelPort_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IParallelPort_setEnabled
IConsole_getPowerButtonHandled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getPowerButtonHandled
IAudioAdapter_getAudioDriver => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_getAudioDriver
ISerialPort_getHostMode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getHostMode
IConsole_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getState
IMachine_setSnapshotFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'snapshotFolder', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setSnapshotFolder
IVRDPServer_setPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'port', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setPort
IVirtualBox_waitForPropertyChange => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'what', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'timeout', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_waitForPropertyChange
IVirtualBox_getSharedFolders => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getSharedFolders
ICustomHardDisk_createDynamicImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_createDynamicImage
IVirtualBox_getMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getMachine
IKeyboard_putScancode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'scancode', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IKeyboard_putScancode
IMachine_deleteSettings => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_deleteSettings
IHostDVDDrive_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostDVDDrive_getDescription
IVirtualBox_findFloppyImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_findFloppyImage
ISATAController_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISATAController_getEnabled
ICustomHardDisk_getCreated => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_getCreated
IVirtualBox_openDVDImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openDVDImage
IFloppyDrive_getImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_getImage
IConsole_getDeviceActivity => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'type', type => 'vbox:DeviceType', attr => {}),
    ], # end parameters
  }, # end IConsole_getDeviceActivity
ISerialPort_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getEnabled
ISystemProperties_getLogHistoryCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getLogHistoryCount
ISnapshot_getParent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getParent
IVirtualBox_getDVDImageUsage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'usage', type => 'vbox:ResourceUsage', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getDVDImageUsage
IConsole_powerButton => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_powerButton
IHost_getMemorySize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getMemorySize
IHardDisk_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getDescription
ISerialPort_getIOBase => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getIOBase
IMachine_setMonitorCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'MonitorCount', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_setMonitorCount
ISerialPort_getServer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISerialPort_getServer
IMachine_getCurrentStateModified => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getCurrentStateModified
IUSBDeviceFilter_setProduct => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'product', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setProduct
INetworkAdapter_setCableConnected => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'cableConnected', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setCableConnected
IMachine_getExtraData => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getExtraData
IVHDImage_createFixedImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVHDImage_createFixedImage
IVHDImage_getFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVHDImage_getFilePath
IVirtualBox_openSession => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'session', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'machineId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openSession
IConsole_getMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_getMachine
IVirtualBox_unregisterMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_unregisterMachine
INetworkAdapter_setNATNetwork => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'NATNetwork', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setNATNetwork
IHost_getProcessorCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getProcessorCount
INetworkAdapter_attachToNAT => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_attachToNAT
IDVDImage_getFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDImage_getFilePath
IAudioAdapter_setAudioController => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'audioController', type => 'vbox:AudioControllerType', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_setAudioController
IVirtualBox_findDVDImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_findDVDImage
IMachine_setClipboardMode => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'clipboardMode', type => 'vbox:ClipboardMode', attr => {}),
    ], # end parameters
  }, # end IMachine_setClipboardMode
IHostFloppyDrive_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostFloppyDrive_getDescription
IUSBDeviceFilter_setName => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setName
IDVDDrive_getPassthrough => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_getPassthrough
IConsole_powerUp => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_powerUp
ISATAController_SetIDEEmulationPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'devicePosition', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'portNumber', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end ISATAController_SetIDEEmulationPort
IUSBDevice_getManufacturer => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getManufacturer
IProgress_getPercent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getPercent
IDVDImage_getAccessible => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDImage_getAccessible
IVirtualBox_getFloppyImages => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getFloppyImages
IWebsessionManager_logoff => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => 'refIVirtualBox', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IWebsessionManager_logoff
IUSBDevice_getSerialNumber => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getSerialNumber
IProgress_getOperationPercent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getOperationPercent
IVirtualDiskImage_createDynamicImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVirtualDiskImage_createDynamicImage
IMachine_getNextExtraDataKey => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getNextExtraDataKey
IHost_getProcessorSpeed => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getProcessorSpeed
IVirtualBox_saveSettings => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_saveSettings
ISnapshot_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISnapshot_getDescription
INetworkAdapter_getMACAddress => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getMACAddress
IVirtualBox_findHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'location', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_findHardDisk
ISession_getType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISession_getType
IVirtualBox_getHardDisks => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getHardDisks
IUSBDeviceFilter_getVendorId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getVendorId
IUSBController_getEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_getEnabled
IDVDDrive_getHostDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_getHostDrive
IVRDPServer_setAllowMultiConnection => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'allowMultiConnection', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_setAllowMultiConnection
IVRDPServer_getPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVRDPServer_getPort
IHostUSBDeviceFilter_setAction => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'action', type => 'vbox:USBDeviceFilterAction', attr => {}),
    ], # end parameters
  }, # end IHostUSBDeviceFilter_setAction
ISystemProperties_setHWVirtExEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'HWVirtExEnabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setHWVirtExEnabled
IAudioAdapter_getAudioController => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_getAudioController
IVMDKImage_createFixedImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_createFixedImage
IUSBDeviceFilter_setPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'port', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setPort
IVirtualBox_getVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getVersion
IUSBDevice_getPortVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getPortVersion
IUSBController_getEnabledEhci => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_getEnabledEhci
IISCSIHardDisk_getTarget => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getTarget
IUSBDeviceFilter_getPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getPort
IMachine_getSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSnapshot
IFloppyDrive_captureHostDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'drive', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyDrive_captureHostDrive
IConsole_saveState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_saveState
IVirtualBox_findMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_findMachine
IParallelPort_getPath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IParallelPort_getPath
IVMDKImage_getCreated => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_getCreated
IMachine_setExtraData => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'value', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setExtraData
IMachine_getAccessible => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getAccessible
IVirtualBox_getProgressOperations => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getProgressOperations
INetworkAdapter_getSlot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getSlot
IVirtualBox_openVirtualDiskImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openVirtualDiskImage
ISystemProperties_getMaxGuestVRAM => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMaxGuestVRAM
IVirtualBox_openRemoteSession => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'session', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'machineId', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'type', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'environment', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openRemoteSession
IHostFloppyDrive_getUdi => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostFloppyDrive_getUdi
INetworkAdapter_getInternalNetwork => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getInternalNetwork
IVirtualBox_getNextExtraDataKey => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'key', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getNextExtraDataKey
IHost_getProcessorDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getProcessorDescription
IFloppyImage_getSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IFloppyImage_getSize
IMachine_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getDescription
IHardDisk_getParent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getParent
ISystemProperties_setDefaultMachineFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'defaultMachineFolder', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setDefaultMachineFolder
INetworkAdapter_getAdapterType => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getAdapterType
ISystemProperties_setDefaultVDIFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'defaultVDIFolder', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setDefaultVDIFolder
IVirtualBox_getHomeFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getHomeFolder
IAudioAdapter_setAudioDriver => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'audioDriver', type => 'vbox:AudioDriverType', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_setAudioDriver
IUSBDeviceFilter_getActive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getActive
IHost_getUTCTime => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getUTCTime
IWebsessionManager_getSessionObject => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => 'refIVirtualBox', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IWebsessionManager_getSessionObject
IISCSIHardDisk_getPort => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IISCSIHardDisk_getPort
INetworkAdapter_setHostInterface => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hostInterface', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_setHostInterface
IUSBDeviceFilter_setMaskedInterfaces => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'maskedInterfaces', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setMaskedInterfaces
IMachine_getMemorySize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getMemorySize
ISystemProperties_getMinGuestRAM => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getMinGuestRAM
IDVDDrive_unmount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_unmount
IVHDImage_createDynamicImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVHDImage_createDynamicImage
IUSBDeviceFilter_getSerialNumber => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getSerialNumber
INetworkAdapter_getTraceEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getTraceEnabled
IHost_getOSVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getOSVersion
IUSBController_setEnabledEhci => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabledEhci', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IUSBController_setEnabledEhci
IUSBDeviceFilter_getMaskedInterfaces => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getMaskedInterfaces
IMachine_setBootOrder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'position', type => 'xsd:unsignedInt', attr => {}),
      SOAP::Data->new(name => 'device', type => 'vbox:DeviceType', attr => {}),
    ], # end parameters
  }, # end IMachine_setBootOrder
IMachine_getAudioAdapter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getAudioAdapter
IMachine_getDVDDrive => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getDVDDrive
ISATAController_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end ISATAController_setEnabled
IMachine_removeSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_removeSharedFolder
IUSBDevice_getRemote => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getRemote
INetworkAdapter_getHostInterface => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end INetworkAdapter_getHostInterface
IUSBDeviceFilter_setVendorId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'vendorId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setVendorId
IUSBDeviceFilter_setSerialNumber => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'serialNumber', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setSerialNumber
IMachine_getSettingsModified => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSettingsModified
IProgress_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getId
IVirtualBox_getSettingsFormatVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getSettingsFormatVersion
IUSBDeviceFilter_setRemote => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'remote', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_setRemote
ISerialPort_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end ISerialPort_setEnabled
IDVDDrive_mountImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'imageId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDDrive_mountImage
IProgress_getOperationCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getOperationCount
IMachine_setStatisticsUpdateInterval => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'statisticsUpdateInterval', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_setStatisticsUpdateInterval
IAudioAdapter_setEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'enabled', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IAudioAdapter_setEnabled
IVirtualBox_getDVDImages => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getDVDImages
IVMDKImage_setFilePath => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_setFilePath
ICustomHardDisk_getLocation => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ICustomHardDisk_getLocation
IHost_getMemoryAvailable => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHost_getMemoryAvailable
IMachine_getBootOrder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'order', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_getBootOrder
IKeyboard_putScancodes => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'scancodes', type => 'xsd:int', attr => {}),
      SOAP::Data->new(name => 'count', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IKeyboard_putScancodes
IMachine_getParent => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getParent
IUSBDevice_getVendorId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getVendorId
IHostUSBDeviceFilter_getAction => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostUSBDeviceFilter_getAction
IProgress_waitForOperationCompletion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'operation', type => 'xsd:unsignedInt', attr => {}),
      SOAP::Data->new(name => 'timeout', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IProgress_waitForOperationCompletion
IHardDisk_getSnapshotId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getSnapshotId
IDVDImage_getId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IDVDImage_getId
IMachine_getSharedFolders => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSharedFolders
IMachine_setDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'description', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setDescription
IMachine_findSnapshot => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_findSnapshot
IUSBController_removeDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'position', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IUSBController_removeDeviceFilter
ISystemProperties_setWebServiceAuthLibrary => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'webServiceAuthLibrary', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setWebServiceAuthLibrary
IHardDisk_getSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getSize
IProgress_cancel => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_cancel
IUSBController_createDeviceFilter => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBController_createDeviceFilter
IMachine_setVRAMSize => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'VRAMSize', type => 'xsd:unsignedInt', attr => {}),
    ], # end parameters
  }, # end IMachine_setVRAMSize
IMachine_setOSTypeId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'OSTypeId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_setOSTypeId
IProgress_getDescription => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IProgress_getDescription
IHardDisk_cloneToImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'filePath', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_cloneToImage
IVirtualBox_createSharedFolder => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'hostPath', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'writable', type => 'xsd:boolean', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_createSharedFolder
IVirtualBox_getHardDisk => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getHardDisk
IVirtualBox_getMachines => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getMachines
ISystemProperties_getHWVirtExEnabled => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getHWVirtExEnabled
IMachine_getUSBController => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getUSBController
IVMDKImage_createDynamicImage => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'size', type => 'xsd:unsignedLong', attr => {}),
    ], # end parameters
  }, # end IVMDKImage_createDynamicImage
IHostDVDDrive_getUdi => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostDVDDrive_getUdi
IUSBDeviceFilter_getProductId => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getProductId
IHostUSBDevice_getState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHostUSBDevice_getState
IVirtualBox_getSettingsFileVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_getSettingsFileVersion
IUSBDeviceFilter_getRevision => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDeviceFilter_getRevision
IUSBDevice_getVersion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IUSBDevice_getVersion
ISystemProperties_setRemoteDisplayAuthLibrary => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'remoteDisplayAuthLibrary', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_setRemoteDisplayAuthLibrary
IMachine_getMonitorCount => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getMonitorCount
ISystemProperties_getWebServiceAuthLibrary => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end ISystemProperties_getWebServiceAuthLibrary
IHardDisk_getAllAccessible => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IHardDisk_getAllAccessible
IMachine_getSessionPid => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IMachine_getSessionPid
IConsole_discardCurrentSnapshotAndState => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IConsole_discardCurrentSnapshotAndState
IProgress_waitForCompletion => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'timeout', type => 'xsd:int', attr => {}),
    ], # end parameters
  }, # end IProgress_waitForCompletion
IVirtualBox_openExistingSession => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'session', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'machineId', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_openExistingSession
IVirtualBox_createMachine => {
    endpoint => 'http://localhost:18083/',
    soapaction => '',
    namespace => 'http://www.virtualbox.org/',
    parameters => [
      SOAP::Data->new(name => '_this', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'baseFolder', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'name', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'id', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end IVirtualBox_createMachine
); # end my %methods

require SOAP::Lite;
require Exporter;
use Carp ();

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

sub _call {
    #######################################################################################################################################################
    # save the additional parameter "vboxhost" which contains an URL with Port information
    my ($self, $method, $vboxhost) = (shift, shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};
    #######################################################################################################################################################
    # set the proxy to $vboxhost instead of $method{endpoint} -> in future vboxhost could contain something like "[*P*<proxyurl>*P*]<hosturl>"
    $self->proxy($vboxhost || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;
    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        if (@templates) {
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            my $method = 'as_'.$typename;
            # TODO - if can('as_'.$typename) {...}
            my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
            push(@parameters, $template->value($result->[2]));
        }
        else {
            push(@parameters, $param);
        }
    }
    #######################################################################################################################################################
    # set the endpoint to $vboxhost instead of $method{endpoint} -> in future vboxhost could contain something like "[*P*<proxyurl>*P*]<hosturl>"
    $self->endpoint($vboxhost)
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
  $self->serializer->register_ns("urn:vbox","interface");
  $self->serializer->register_ns("http://www.virtualbox.org/","vbox");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/soap/","soap");
    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
    }
}
no strict 'refs';
for my $method (@EXPORT_OK) {
    my %method = %{$methods{$method}};
    *$method = sub {
        my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
            ? ref $_[0]
                ? shift # OBJECT
                # CLASS, either get self or create new and assign to self
                : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
            # function call, either get self or create new and assign to self
            : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
        $self->_call($method, @_);
    }
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;

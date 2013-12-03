Dim filesys, srcfile, srcfilename, fline,  dstfilename, dstfile, myshell, netuse
Dim tmpstr, elems, instdrv, instpart, partcfg, partbios, partuefi
Set myshell = WScript.createObject("WScript.Shell")
Set netuse = myshell.Exec("net use")
Dim drvletter
Do While Not netuse.StdOut.AtEndOfStream
	tmpstr = netuse.StdOut.ReadLine()
	if InStr(tmpstr,"install") > 0 Then
		Do while InStr(tmpstr,"  ") > 0
			tmpstr = Replace(tmpstr,"  "," ")
		Loop
		elems = Split(tmpstr)
		drvletter=elems(1)
	End If
Loop
instdrv = myshell.ExpandEnvironmentStrings ( "%INSTALLTO%" )
if InStr(instdrv,"%INSTALLTO%") Then
	Set myenv=myshell.Environment("User")
	instdrv = myenv("INSTALLTO")
End If
if instdrv = "" Then
	Set myenv=myshell.Environment("System")
	instdrv = myenv("INSTALLTO")
End If
if instdrv = "" Then
	instdrv = "0:0"
End If

Dim strpoint
strpoint = InStr(instdrv, ":")
if strpoint Then
	tmpstr = instdrv
	instdrv = left(tmpstr,strpoint-1)
	instpart = mid(tmpstr,strpoint+1)
End If

partcfg = myshell.ExpandEnvironmentStrings ( "%PARTCFG%" )
if InStr(partcfg,"%PARTCFG%") Then
	Set myenv=myshell.Environment("User")
	partcfg = myenv("%PARTCFG%")
End If
if instdrv = "" Then
	Set myenv=myshell.Environment("System")
	partcfg = myenv("%PARTCFG%")
End If

strpoint = InStr(partcfg, "[BIOS]")
If strpoint Then
	partbios = Mid(partcfg, strpoint+6)
	strpoint = InStr(partbios, "[UEFI]")
	If strpoint Then
		partuefi = Mid(partbios, strpoint+6)
		partbios = Left(partbios, strpoint-1)
	End If
End If

Set filesys = CreateObject("Scripting.FileSystemObject")
dim notefi
notefi=1
if filesys.FileExists(drvletter&"\utils\windows\detectefi.exe") then
	notefi = myshell.run(drvletter&"\utils\windows\detectefi.exe",1,true)
end if
srcfilename = WScript.Arguments.Item(0)
dstfilename = WScript.Arguments.Item(1)
Set srcfile = filesys.OpenTextFile(srcfilename,1)
Set dstfile = filesys.OpenTextFile(dstfilename,2,True)
dim partitionscheme
Do Until srcfile.AtEndOfStream
        fline = srcfile.ReadLine
	if notefi=0 then
		fline = Replace(fline,"==BOOTPARTITIONS==","<CreatePartitions><CreatePartition><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition><CreatePartition><Order>2</Order><Type>MSR</Type><Size>128</Size></CreatePartition><CreatePartition><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition></CreatePartitions>")

		if partuefi<>"" Then
			fline = Replace(fline,"==DISKCONFIG==", partuefi)
		else
			fline = Replace(fline,"==DISKCONFIG==","<DiskID>" & instdrv & "<Disk></DiskID><WillWipeDisk>true</WillWipeDisk><CreatePartitions><CreatePartition><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition><CreatePartition><Order>2</Order><Type>MSR</Type><Size>128</Size></CreatePartition><CreatePartition><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition></CreatePartitions></Disk>")
		end if

		if instpart<>"0" Then
			fline = Replace(fline,"==INSTALLTOPART==", instpart)
		else
			fline = Replace(fline,"==INSTALLTOPART==","3")
		end if
	else
		fline = Replace(fline,"==BOOTPARTITIONS==","<CreatePartitions><CreatePartition><Order>1</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition></CreatePartitions>")

		if partbios<>"" Then
			fline = Replace(fline,"==DISKCONFIG==", partbios)
		else
			fline = Replace(fline,"==DISKCONFIG==", "<DiskID>" & instdrv & "<Disk></DiskID><WillWipeDisk>true</WillWipeDisk><CreatePartitions><CreatePartition><Order>1</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition></CreatePartitions></Disk>")
		end if

		if instpart<>"0" Then
			fline = Replace(fline,"==INSTALLTOPART==",instpart)
		else
			fline = Replace(fline,"==INSTALLTOPART==","1")
		end if
	end if
	
	fline = Replace(fline,"==INSTALLTODISK==",instdrv)

	dstfile.WriteLine(Replace(fline,"==INSTALLSHARE==",drvletter))
Loop

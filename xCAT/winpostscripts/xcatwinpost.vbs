'This script is used to run postscripts for Windows compute node
Dim filesys, myshell
Dim nodename, origpostscript, mypostscript, mypostbootscript
Dim output, tmpstr, startpoint
Dim fileread, filewrite, filewritepost, filewritepostboot, fline
Dim flagwp, flagwpb
Dim logname,loghandler


'Ingore the error box to avoid the stop of postscript running
On Error Resume Next


logname = "c:\xcatpost\xcat.log"

'Initialize the shell and fs objects
Set myshell = WScript.createObject("WScript.Shell")
Set filesys = CreateObject("Scripting.FileSystemObject")

'Open the log file for writting
Set loghandler = filesys.OpenTextFile(logname, 8, True)
loghandler.WriteLine "=========================================="
loghandler.WriteLine now
loghandler.WriteLine "Get in xcatwinpost.vbs"

'Read envrironment variables from c:\xcatpost\xcatenv
Set fileread = filesys.OpenTextFile("c:\xcatpost\xcatenv",1)
Do Until fileread.AtEndOfStream
    fline = fileread.ReadLine
    strpoint = InStr(fline, "NODENAME=")
    If strpoint Then
        nodename = Mid(fline, strpoint+9)
    End If
Loop
loghandler.WriteLine "The nodename is: " & nodename

'Get the postscripts from xCAT management
origpostscript = "c:\xcatpost\mypostscript." & nodename
mypostscript = "c:\xcatpost\mypostscript.cmd"
mypostbootscript = "c:\xcatpost\mypostbootscript.cmd"

' Debug
'WScript.echo "orig mypostscript"& origpostscript

'Check the existence of mypostscript file
If NOT filesys.FileExists(origpostscript) Then
   loghandler.WriteLine "Cannot find the original mypostscript: " & origpostscript
   loghandler.Close
   'WScript.echo "QUIT"
   WScript.quit [1]
End If

'Create mypostscript and mypostbootscript from original postscript which was copied from xCAT MN
Set fileread = filesys.OpenTextFile(origpostscript, 1)

Set filewritepost = filesys.OpenTextFile(mypostscript, 2, True)
Set filewritepostboot = filesys.OpenTextFile(mypostbootscript, 2, True)

flagwp = 0
flagwpb = 0
Do Until fileread.AtEndOfStream
    fline = fileread.ReadLine

    If InStr(fline, "|") Then
        ' Ignore the char |
        ' Do nothing
    ElseIf InStr(fline, "osimage-postscripts-start-here") Or InStr(fline, "node-postscripts-start-here") Then
        flagwp = 1
    ElseIf InStr(fline, "osimage-postscripts-end-here") Or InStr(fline, "node-postscripts-end-here") Then
        flagwp = 0
    ElseIf InStr(fline, "osimage-postbootscripts-start-here") Or InStr(fline, "node-postbootscripts-start-here") Then
        flagwpb = 1
    ElseIf InStr(fline, "osimage-postbootscripts-end-here") Or InStr(fline, "node-postbootscripts-end-here") Then
        flagwpb = 0
    ElseIf InStr(fline, "=") Then
        ' Set the environment variables
        tmpstr = "Set "&fline
        ' Ignore the char '
        tmpstr = Replace(tmpstr, "'", "")
        filewritepost.WriteLine tmpstr
        filewritepostboot.WriteLine tmpstr
    ElseIf flagwp Then
        ' Run script with runpost.vbs
        fline = "c:\xcatpost\runpost.vbs " & fline
        filewritepost.WriteLine fline
    ElseIf flagwpb Then
        ' Run script with runpost.vbs
        fline = "c:\xcatpost\runpost.vbs " & fline
        filewritepostboot.WriteLine fline
    End If
Loop

fileread.Close
filewritepost.Close
filewritepostboot.Close

loghandler.WriteLine "mypostscript and mypostbootscript have been created"

'Generate the setup computed file which is used to initiate the running of postbootscripts
If NOT filesys.FolderExists("C:\Windows\Setup\Scripts\") Then
    filesys.CreateFolder("C:\Windows\Setup\Scripts\")
End If

'Open it with appending mode
set filewrite = filesys.OpenTextFile("C:\Windows\Setup\Scripts\SetupComplete.cmd", 8, True)
filewrite.WriteLine "cmd /c call " & mypostbootscript
filewrite.Close

loghandler.WriteLine "C:\Windows\Setup\Scripts\SetupComplete.cmd has been created."

loghandler.WriteLine "To run mypostscript"
loghandler.WriteLine ""

loghandler.Close
' Run mypostscript
Set myshell = WScript.createObject("WScript.Shell")
myshell.Run "cmd /c " & mypostscript, 0, True
'Do While Not output.StdOut.AtEndOfStream
'      fline = output.StdOut.ReadLine()
'      WScript.echo fline
'Loop


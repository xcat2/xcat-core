Dim myshell, filesys 
Dim args, pname, pargs, cmdname
Dim logname, loghandler, fline, output

'Ingore the error box to avoid the stop of postscript running
On Error Resume Next

'WScript.echo "get in runpost"

logname = "c:\xcatpost\xcat.log"

'Initialize the shell and fs objects
Set myshell = WScript.createObject("WScript.Shell")
Set filesys = CreateObject("Scripting.FileSystemObject")

'Open the log file for writting
Set loghandler = filesys.OpenTextFile(logname, 8, True)

' Get script name and arguments
Set args = WScript.Arguments
If args.Count <= 0 Then
    loghandler.Close
    WScript.Quit
ElseIf args.Count = 1 Then
    pname = args(0)
    pargs = ""
ElseIf args.Count > 1 Then
    pname = args(0)
    For i = 1 to args.Count - 1
       pargs = pargs & " " & args(i)
    Next
End If

If Not filesys.FileExists("c:\xcatpost\" & pname) Then
    loghandler.WriteLine "Cannot find file: c:\xcatpost\" & pname 
    loghandler.Close
    WScript.Quit
End If

cmdname = "cmd /c "
if Right(pname, 4) = ".bat" Or Right(pname, 4) = ".cmd" Then
    cmdname = cmdname & "call "
End If

cmdname = cmdname & " c:\xcatpost\" & pname & " " & pargs

loghandler.WriteLine "=========================================="
loghandler.WriteLine now
loghandler.WriteLine "Run script: " & pname & " " & pargs

'Run command
'WScript.echo cmdname
Set output = myshell.Exec(cmdname)

' Handle the output from the script
Do While Not output.StdOut.AtEndOfStream
      fline = output.StdOut.ReadLine()
      loghandler.WriteLine fline
Loop

loghandler.WriteLine "The return code is: " & output.ExitCode
loghandler.WriteLine ""

loghandler.Close

$command=@{'command'='nextdestiny'}
if (!(Test-Path HKCU:\Software\xCAT)) {
        mkdir HKCU:\Software\xCAT
	$certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","CurrentUser")
	$certstore.Open([System.Security.Cryptopgraphy.X509Certificates.OpenFlags]'Readwrite')
	$cacert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$env:instdrv\xcat\ca.pem")
	Set-ItemProperty HKCU:\Software\xCAT cacertthumb $cacert.thumbprint
	Set-ItemProperty HKCU:\Software\xCAT serveraddress $env:master
	Set-ItemProperty HKCU:\Software\xCAT servername $env:mastername
}
Send-xCATCommand $command

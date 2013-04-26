$command=@{'command'='nextdestiny'}
if (!(Test-Path HKLM:\Software\Policies\Microsoft\SystemCertificates\AuthRoot)) {
	mkdir HKLM:\Software\Policies\Microsoft\SystemCertificates\AuthRoot
	Set-ItemProperty HKLM:\Software\Policies\Microsoft\SystemCertificates\AuthRoot DisableRootAutoUpdate 1
}
if (!(Test-Path HKLM:\Software\xCAT)) {
        mkdir HKLM:\Software\xCAT
	$certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store("xCAT","LocalMachine")
	$certstore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'Readwrite')
	$cacert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$env:instdrv\xcat\ca.pem")
	Set-ItemProperty HKLM:\Software\xCAT cacertthumb $cacert.thumbprint
	Set-ItemProperty HKLM:\Software\xCAT serveraddress $env:master
	Set-ItemProperty HKLM:\Software\xCAT servername $env:mastername
}
Send-xCATCommand $command

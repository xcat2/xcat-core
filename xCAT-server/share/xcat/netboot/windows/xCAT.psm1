# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
# This function specifically validates that the peer we are talking to is signed by the xCAT blessed CA and no other CA
Function VerifyxCATCert ($sender, $cert, $chain, $polerrs) {
	if ($polerrs -ne "None" -and $polerrs -ne "RemoteCertificateChainErrors") { return $false } #if the overall policy suggests rejection, go with it
	#why do we tolerate RemoteCertificateChainErrors?  Because we are going to check specifically for the CA configured for this xCAT installation
	#we chose not to add xCAT's CA to the root store, as that implies the OS should trust xCAT's CA for non-xCAT related things.  That is madness.
	#Of course, that's the madness typical with x509, but we need not propogate the badness...
	#we are measuring something more specific than 'did any old CA sign this', we specifically want to assue the signer CA is xCAT's 
        foreach ($cert in $chain.chainElements) {
		if ($script:xcatcacert.thumbprint.Equals($cert.Certificate.thumbprint)) {
			return $true
		}
        }
	return $false
}

#we import the xCAT certificate authority into the appropriate scope.
#It's not trusted by system policy, but our overidden verify function will find it.  Too bad MS doesn't allow us custom store names under the user
#repository for whatever reason.  We'll just 'import' it every session from file, which is harmless to do multiple times
#this isn't quite as innocuous as the openssl mechanisms to do this sort of thing, but it's as close as I could figure to get
Function Import-xCATCA ( $certpath ) {
	$script:xcatcacert=Import-Certificate -FilePath $certpath -CertStoreLocation Cert:\CurrentUser\My
}

#this removes the xCAT CA from trust store, if user wishes to explicitly remove xCAT key post deploy
#A good idea for appliances that want to not show weird stuff.  The consequences of not calling it are harmless: a useless extra public cert
#in admin's x509 cert store
Function Remove-xCATCA ( $certpath ) {
	Import-xCATCA($certpath) #this seems insane, but it's easiest way to make sure we have the correct path
	rm $script:xcatcacert.PSPath
}

#specify a client certificate to use in pfx format
Function Set-xCATClientCertificate ( $pfxPath ) {
	$script:xcatclientcert=Import-pfxCertificate $pfxPath -certStoreLocation cert:\currentuser\my
}
Function Remove-xCATClientCertificate( $pfxPath ) {
	xCAT-Set-Client-Certificate($pfxpath)
	rm cert:\currentuser\my\$script:xcatclientcert.thumbprint
}

#key here is that we might have two certificates:
#-one intended to identify the system that was deployed by xcat
#-one intended to identify the user to do things like 'rpower'
#however, user will just have to control it by calling Set-xCATClientCertificate on the file for now
#TODO: if user wants password protected PFX file, we probably would want to import it once and retain thumb across sessions...
Function Select-xCATClientCert ($sender, $targetHost, $localCertificates, $remoteCertificate,$acceptableIssuers) {
	$script:xcatclientcert
}
Function Connect-xCAT { 
	Param(
		$mgtServer,
		$mgtServerPort=3001,
		$mgtServerAltName=$mgtServer
	)
	$script:xcatconnection = New-Object Net.Sockets.TcpClient($mgtServer,$mgtServerPort)
	$script:verifycallback = Get-Content Function:\VerifyxCATCert
	$script:xcatstream = $script:xcatconnection.GetStream()
	$script:securexCATStream = New-Object System.Net.Security.SSLStream($script:xcatstream,$false,$script:verifycallback)
	$script:securexCATStream.AuthenticateAsClient($mgtServerAltName)
}

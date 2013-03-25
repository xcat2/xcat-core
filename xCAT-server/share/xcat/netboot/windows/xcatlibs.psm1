# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
# This function specifically validates that the peer we are talking to is signed by the xCAT blessed CA and no other CA
Function xCAT-Verify-Cert ($sender, $cert, $chain, $polerrs) {
	if ($polerrs -ne "None") { return $false } #if the overall policy suggests rejection, go with it
	#now, system policy suggests that everything is ok, but we want to be more picky, because we 
	#are measuring something more specific than 'did any old CA sign this', we specifically want to assue the signer CA is xCAT's 
	#TODO: perhaps ignore the RemoteCertificateChainErrors condition and chase a chain of our own creation
	#that chain could live outside the user or system wide root to avoid giving xCAT the power to sign certs for things it shouldn't
        foreach ($cert in $chain.chainElements) {
		if ($script:xcatcacert.thumbprint -eq $cert.Certificate.thumprint) {
			return $true
		}
        }
	return $false
}

#we import the xCAT certificate authority into the appropriate scope
#we have to use localmachine in order to avoid interactive prompt, meaning we need admin for this one, besides
#this means admin installs CA cert for everyone
#TODO: use cert:\currentuser\root when not administrator to facilitate xCAT-client case, take the prompt once
Function xCAT-Import-CA ( $certpath ) {
	$script:xcatcacert=Import-Certificate -FilePath $certpath -CertStoreLocation Cert:\LocalMachine\root 
}

#this removes the xCAT CA from trust store, if user wishes to explicitly distrust xCAT post deploy
Function xCAT-Remove-CA ( $certpath ) {
	xCAT-Import-CA($certpath) #this seems insane, but it's easiest way to make sure we have the correct path
	rm $script:xcatcacert.PSPath
}

#specify a client certificate to use in pfx format
#we put this one in the user's store instead of system wide
Function xCAT-Set-Client-Certificate ( $pfxPath ) {
	$script:xcatclientcert=Import-pfxCertificate $pfxPath -certStoreLocation cert:\currentuser\my
}
Function xCAT-Remove-Client-Certificate( $pfxPath ) {
	xCAT-Set-Client-Certificate($pfxpath)
	rm cert:\currentuser\my\$script:xcatclientcert.thumbprint
}

#key here is that we might have two certificates:
#-one intended to identify the system that was deployed by xcat
#-one intended to identify the user to do things like 'rpower'
#TODO: argument to specify whether this is a human or machine.  Default would be human and machine invocation would be in scripts
Function xCAT-Select-Cert ($sender, $targetHost, $localCertificates, $remoteCertificate,$acceptableIssuers) {
	$script:xcatclientcert
}
Function xCAT-Connect ( 
	Param(
		$mgtServer,
		$mgtServerAltName=$mgtServer
	)

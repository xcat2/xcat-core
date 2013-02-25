# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
# This function specifically validates that the peer we are talking to is signed by the xCAT blessed CA and no other CA
Function xCAT-Verify-Cert ($sender, $cert, $chain, $polerrs) {
        foreach ($cert in $chain.chainElements) {
                $cathumb=$cert.Certificate.thumbprint
        }
	if ($scrpt:xcatcacert.thumbprint -ne $cathumb) {
		return $false
	}
	return $true
}

#we import the xCAT certificate authority into the appropriate scope
Function xCAT-Import-CA ( $certpath ) {
	$script:xcatcacert=Import-Certificate -FilePath $certpath -CertStoreLocation Cert:\LocalMachine\root 
}
Function xCAT-Remove-CA () {
	rm cert:\localmachine\root\$script:xcatcacert.thumbprint
}


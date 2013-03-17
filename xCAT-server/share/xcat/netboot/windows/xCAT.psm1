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
	Set-xCATClientCertificate($pfxpath)
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
		$mgtServer=$xcathost,
		$mgtServerPort=3001,
		$mgtServerAltName=$mgtServer
	)
	$script:xcatconnection = New-Object Net.Sockets.TcpClient($mgtServer,$mgtServerPort)
	$verifycallback = Get-Content Function:\VerifyxCATCert
	$certselect = Get-Content Function:\Select-xCATClientCert
	$script:xcatstream = $script:xcatconnection.GetStream()
	$script:securexCATStream = New-Object System.Net.Security.SSLStream($script:xcatstream,$false,$verifycallback,$certselect)
	$script:securexCATStream.AuthenticateAsClient($mgtServerAltName)
	$script:xcatwriter = New-Object System.IO.StreamWriter($script:securexCATStream)
	$script:xcatreader = New-Object System.IO.StreamReader($script:securexCATStream)
}

Function Get-NodeInventory {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange,
		[parameter(ValueFromRemainingArguments=$true)] $inventoryType
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rinv';'noderange'=$nodeRange;'args'=@($inventoryType)}
	Send-xCATCommand($xcatrequest)
}
Function Get-NodeBeacon {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rbeacon';'noderange'=$nodeRange;'args'=@('stat')}
	Send-xCATCommand($xcatrequest)
}
Function Set-NodeBeacon {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange,
		$newBeaconState
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rbeacon';'noderange'=$nodeRange;'args'=@($newBeaconState)}
	Send-xCATCommand($xcatrequest)
}
Function Get-NodePower {
	Param(
		[parameter(Position=0,ValueFromPipeLine=$true)] $nodeRange
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rpower';'noderange'=$nodeRange;'args'=@('stat')}
	Send-xCATCommand($xcatrequest)
}
Function Merge-xCATData { #xcoll attempt
	$groupeddata=$input|Group-Object -Property "node"
	foreach ($nodedata in $groupeddata) {
		 New-MergedxCATData $nodedata.Group
	}
	
}
Function Set-NodePower {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange,
		[parameter(HelpMessage="The power action to perform (on/off/boot/reset)")] $powerState="stat"
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rpower';'noderange'=$nodeRange;'args'=@($powerState)}
	Send-xCATCommand($xcatrequest)
}
Function Get-Nodes {
	Param(
		[parameter(Position=0,ValueFromPipeLine=$true)] $nodeRange,
		[parameter(ValueFromRemainingArguments=$true)] $tableAndColumn
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='nodels';'noderange'=$nodeRange;'args'=@($tableAndColumn)}
	Send-xCATCommand($xcatrequest)
}
Function Get-NodeVitals {
	Param(
		[parameter(Position=0,ValueFromPipeLine=$true)] $nodeRange,
		[parameter(ValueFromRemainingArguments=$true)] $vitalTypes="all"
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='rvitals';'noderange'=$nodeRange;'args'=@($vitalTypes)}
	Send-xCATCommand($xcatrequest)
}
Function Send-xCATCommand {
	Param(
		$xcatRequest
	)
	Connect-xCAT
	$requestxml = "<xcatrequest>`n`t<command>"+$xcatRequest.command+"</command>`n"
	if ($xcatRequest.noderange) {
		if ($xcatRequest.noderange.PSObject.TypeNames[0] -eq "xCATNodeData") {
			$xcatRequest.noderange =  $xcatRequest.noderange.Node
		}
		if ($xcatRequest.noderange -is [System.Array]) { #powershell wants to arrayify commas because it can't make up its mind 
								 #whether it's a scripting language or a shell language, try to undo the 
								 #damage
			$nrparts=@()
			foreach ($nr in $xcatRequest.noderange) {
				if ($nr -is [System.String]) {
					$nrparts += $nr
				} elseif ($nr.PSObject.TypeNames[0] -eq "xCATNodeData") {
					$nrparts += $nr.Node
				}
			}
			$xcatRequest.noderange=[string]::Join(",",$nrparts);
		}
		$requestxml = $requestxml + "`t<noderange>"+$xcatRequest.noderange+"</noderange>`n"
	}
        foreach ($arg in $xcatRequest.args) {
		if ($arg) {
			if ($arg -is [System.Array]) {
				$arg=[string]::join(",",$arg);
			}
			$requestxml = $requestxml + "`t<arg>"+$arg+"</arg>`n"
		}
	}
	$requestxml = $requestxml + "</xcatrequest>`n"
	$script:xcatwriter.WriteLine($requestxml)
	$script:xcatwriter.Flush()
	$serverdone=0
	while (! $serverdone -and $script:xcatreader) {
		$responsexml=""
		$lastline=""
		while ($lastline -ne $null -and ! $lastline.Contains("</xcatresponse>") -and $script:xcatreader) {
			$lastline = $script:xcatreader.ReadLine()
			$responsexml = $responsexml + $lastline
		}
		[xml]$response = $responsexml
		foreach ($elem in $response.xcatresponse.node) {
			New-xCATDataFromXmlElement $elem -NodeRangeHint $xcatRequest.noderange
		}
		#$response.xcatresponse.node.name
		#$response.xcatresponse.node.data
		if ($response.xcatresponse.serverdone -ne $null) { $serverdone=1 }
	}
}

Function New-MergedxCATData { #takes an arbitrary number of nodeData objects and spits out one
	Param(
		$nodeData
	)
	$myobj = @{}
	$myobj.dataObjects=@()
	$myobj.NodeRange = $nodeData[0].Node
	foreach ($data in $nodeData) {
		$rangedata = $data|select-object -ExcludeProperty Node *
		$rangedata.PSObject.TypeNames.RemoveAt(0)
		$myobj.dataObjects = $myobj.dataObjects  + $rangedata
	}
	$newobj = New-Object -TypeName PSObject -Prop $myobj
	$newobj.PSObject.TypeNames.Insert(0,'xCATNodeRangeData')
	return $newobj
}
Function New-xCATDataFromXmlElement {
	Param(
		$xmlElement,
		$NodeRangeHint
	)
	$myprops = @{}
	if ($NodeRangeHint) { #hypothetically, 'xcoll' implementation might find this handy
		$myprops.NodeRangeHint=$NodeRangeHint
	}
	if ($xmlElement.name) {
		$myprops.Node=$xmlElement.name
	}
	if ($xmlElement.data.desc) {
		$myprops.Description=$xmlElement.data.desc
	}
	if ($xmlElement.data.contents) {
		$myprops.Data=$xmlElement.data.contents
	} else {
		$myprops.Data=""
	}
	$myobj=New-Object -TypeName PSObject -Prop $myprops
	$myobj.PSObject.TypeNames.Insert(0,'xCATNodeData')
	return $myobj
}
New-Alias -name rpower -value Set-NodePower
New-Alias -name rvitals -value Get-Nodevitals
New-Alias -name rinv -value Get-NodeInventory
New-Alias -name rbeacon -value Set-NodeBeacon
New-Alias -name nodels -value Get-Nodes
Export-ModuleMember -function *-* -Alias *

		
		


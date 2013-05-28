# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
# This function specifically validates that the peer we are talking to is signed by the xCAT blessed CA and no other CA
Function Import-xCATConfig ($credentialPackage) {
	$shell = New-Object -com shell.application
    $credentialPackage = $credentialPackage -replace '^\.\\',''
    if (-not ($credentialPackage -match '\\')) {
        $mypath = Get-Location
        $credentialPackage = $mypath.Path + "\"+ $credentialPackage
    }
	$credpkg = $shell.namespace($credentialPackage)
	$randname = [System.IO.Path]::GetRandomFileName()
	Push-Location
	mkdir $env:temp+"\"+$randname
	Set-Location $env:temp+"\"+$randname
	$tmpdir = $shell.namespace((Get-Location).Path)
	$tmpdir.CopyHere($credpkg.items(),0x14)
	if (!(Test-Path HKCU:\Software\xCAT)) {
		mkdir HKCU:\Software\xCAT
	}
	if (Test-Path xcat.cfg) {
		$cfgdata=Get-Content xcat.cfg 
		$keyvalue = $cfgdata.Split("=")
		$servername = $keyvalue[1]
		Set-ItemProperty HKCU:\Software\xCAT servername $servername
	}
	if (Test-Path ca.pem) {
		ImportxCATCA ca.pem
	}
	if (Test-Path user.pfx) {
		SetxCATClientCertificate user.pfx
	}
	Pop-Location
}
Function VerifyxCATCert ($sender, $cert, $chain, $polerrs) {
	if ($polerrs -ne "None" -and $polerrs -ne "RemoteCertificateChainErrors") { return $false } #if the overall policy suggests rejection, go with it
	#why do we tolerate RemoteCertificateChainErrors?  Because we are going to check specifically for the CA configured for this xCAT installation
	#we chose not to add xCAT's CA to the root store, as that implies the OS should trust xCAT's CA for non-xCAT related things.  That is madness.
	#Of course, that's the madness typical with x509, but we need not propogate the badness...
	#we are measuring something more specific than 'did any old CA sign this', we specifically want to assue the signer CA is xCAT's 
	if (Test-Path HKCU:\Software\xCAT) {
		$mythumb=Get-ItemProperty HKCU:\Software\xCAT
	} else {
		$mythumb=Get-ItemProperty HKLM:\Software\xCAT
	}
        foreach ($cert in $chain.chainElements) {
		if ($mythumb.cacertthumb.Equals($cert.Certificate.thumbprint)) {
			return $true
		}
        }
	return $false
}

#we import the xCAT certificate authority into the appropriate scope.
#It's not trusted by system policy, but our overidden verify function will find it.  Too bad MS doesn't allow us custom store names under the user
#repository for whatever reason.  We'll just 'import' it every session from file, which is harmless to do multiple times
#this isn't quite as innocuous as the openssl mechanisms to do this sort of thing, but it's as close as I could figure to get
Function ImportxCATCA ( $certpath ) {
	$xcatstore = New-Object System.Security.Cryptography.X509Certificates.X509Store("xCAT","CurrentUser")
    $certpath = $certpath -replace '^\.\\',''
    if (-not ($certpath -match '\\')) { 
        $mypath=Get-Location
        $certpath = $mypath.Path + "\" + $certpath
    }
	$cacert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certpath)
	$xcatstore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'Readwrite')
	$xcatstore.Add($cacert)
	Set-ItemProperty HKCU:\Software\xCAT cacertthumb $cacert.thumbprint
}

#this removes the xCAT CA from trust store, if user wishes to explicitly remove xCAT key post deploy
#A good idea for appliances that want to not show weird stuff.  The consequences of not calling it are harmless: a useless extra public cert
#in admin's x509 cert store
Function RemovexCATCA {
	$mythumb=Get-ItemProperty HKCU:\Software\xCAT
	rm cert:\CurrentUser\xCAT\$mythumb.cacertthumb
}

#specify a client certificate to use in pfx format
Function SetxCATClientCertificate ( $pfxPath ) {
    $pfxPath = $pfxPath -replace '^\.\\',''
    if (-not ($pxfPath -match '\\')) { 
        $mypath=Get-Location
        $pfxPath = $mypath.Path + "\" + $pfxPath
    }
        
	$xcatstore = New-Object System.Security.Cryptography.X509Certificates.X509Store("xCAT","CurrentUser")
	$xcatstore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'Readwrite')
	$xcatclientcert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxpath)
	$xcatstore.Add($xcatclientcert)
	Set-ItemProperty HKCU:\Software\xCAT usercertthumb $xcatclientcert.thumbprint
}
Function RemovexCATClientCertificate {
	SetxCATClientCertificate($pfxpath)
	$mythumb=Get-ItemProperty HKCU:\Software\xCAT
	if (!$mythumb) {
		$mythumb=Get-ItemProperty HKLM:\Software\xCAT
	}
	rm cert:\currentuser\my\$mythumb.usercertthumb
}

#key here is that we might have two certificates:
#-one intended to identify the system that was deployed by xcat
#-one intended to identify the user to do things like 'rpower'
#however, user will just have to control it by calling Set-xCATClientCertificate on the file for now
#TODO: if user wants password protected PFX file, we probably would want to import it once and retain thumb across sessions...
Function SelectxCATClientCert ($sender, $targetHost, $localCertificates, $remoteCertificate,$acceptableIssuers) {
	if (!(Test-Path HKCU:\Software\xCAT)) { #in this case, we might be operating in system context for install instrumentation
		$myreg=Get-ItemProperty HKLM:\Software\xCAT
		if ($myreg) { #confirmed that we have a machine level authentication setup to fall back upon
			$mycertthumb=$myreg.usercertthumb
			Get-Item cert:\LocalMachine\xCAT\$mycertthumb
		}
	} else {
		$myreg = Get-ItemProperty HKCU:\Software\xCAT
		$mythumb=(Get-ItemProperty HKCU:\Software\xCAT).usercertthumb
		Get-Item cert:\CurrentUser\xCAT\$mythumb
	}
}
Function Set-xCATServer {
	Param(
		[Parameter(Mandatory=$true)] $xCATServer
	)
	Set-ItemProperty HKCU:\Software\xCAT serveraddress $xCATServer
}
Function ConnectxCAT { 
	Param(
		$mgtServer,
		$mgtServerPort=3001,
		$mgtServerAltName
	)
	if (! $mgtServer) {
		if (Test-Path HKCU:\Software\xCAT) {
			$mgtServer=(Get-ItemProperty HKCU:\Software\xCAT).serveraddress
			if (! $mgtServer) {
				$mgtServer=(Get-ItemProperty HKCU:\Software\xCAT).servername
			}
		} else {
			if (! $mgtServer) {
				$mgtServer=(Get-ItemProperty HKLM:\Software\xCAT).serveraddress
			}
			if (! $mgtServer) {
				$mgtServer=(Get-ItemProperty HKLM:\Software\xCAT).servername
			}
		}
	}
	if (! $mgtServerAltName) {
		if (Test-Path HKCU:\Software\xCAT) {
			$mgtServerAltName=(Get-ItemProperty HKCU:\Software\xCAT).servername
		} elseif (Test-Path HKLM:\Software\xCAT) { #node reporting command
			$mgtServerAltName=(Get-ItemProperty HKLM:\Software\xCAT).servername
		}
	}
	$script:xcatconnection = New-Object Net.Sockets.TcpClient($mgtServer,$mgtServerPort)
	if (! $script:xcatconnection) { 
		return $false
	}
	$verifycallback = Get-Content Function:\VerifyxCATCert
	$certselect = Get-Content Function:\SelectxCATClientCert
	$script:xcatstream = $script:xcatconnection.GetStream()
	$haveclientcert=0
	if (Test-Path HKCU:\Software\xCAT) {
		$xcreg=Get-ItemProperty HKCU:\Software\xCAT
		if ($xcreg.usercertthumb) {
			$haveclientcert=1
		}
	} elseif (Test-Path HKLM:\Software\xCAT) { #intended for localsystem context for node->xCAT calls
		$xcreg=Get-ItemProperty HKLM:\Software\xCAT
		if ($xcreg.usercertthumb) {
			$haveclientcert=1
		}
	}
	if ($haveclientcert) {
		$script:securexCATStream = New-Object System.Net.Security.SSLStream($script:xcatstream,$false,$verifycallback,$certselect)
	} else {
		$script:securexCATStream = New-Object System.Net.Security.SSLStream($script:xcatstream,$false,$verifycallback)
	}
	$script:securexCATStream.AuthenticateAsClient($mgtServerAltName)
	$script:xcatwriter = New-Object System.IO.StreamWriter($script:securexCATStream)
	$script:xcatreader = New-Object System.IO.StreamReader($script:securexCATStream)
	$true
}

Function Clear-NodeEventlog {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange
	)
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='reventlog';'noderange'=$nodeRange;'args'=@('clear')}
	Send-xCATCommand($xcatrequest)
}
Function Get-NodeEventlog {
	Param(
		[parameter(ValueFromPipeLine=$true)] $nodeRange,
		[parameter(ValueFromRemainingArguments=$true)] $eventCount
	)
    if (-not $eventCount) {
        $eventCount = "all"
    }
	$pipednr=@($input)
	if ($pipednr)  { $nodeRange = $pipednr }
	$xcatrequest=@{'command'='reventlog';'noderange'=$nodeRange;'args'=@($eventCount)}
	Send-xCATCommand($xcatrequest)
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
Function Get-NodeBoot {
    Param(
        [parameter(ValueFromPipeLine=$true)] $nodeRange
    )
    $pipednr=@($input)
    if ($pipednr) { $nodeRange = $pipednr }
    $xcatrequest=@{'command'='rsetboot';'noderange'=$nodeRange;'args'=@('stat')}
    Send-xCATCommand($xcatrequest)
}
Function Get-NodeDeploy {
    Param(
        [parameter(ValueFromPipeLine=$true)] $nodeRange
    )
    $pipednr=@($input)
    if ($pipednr) { $nodeRange = $pipednr }
    $xcatrequest=@{'command'='nodeset';'noderange'=$nodeRange;'args'=@('stat')}
    Send-xCATCommand($xcatrequest)
}
Function Set-NodeDeploy {
    Param(
        [parameter(ValueFromPipeLine=$true)] $nodeRange,
        $deployAction
    )
    $pipednr=@($input)
    if ($pipednr) { $nodeRange = $pipednr }
    $xcatrequest=@{'command'='nodeset';'noderange'=$nodeRange;'args'=@($deployAction)}
    Send-xCATCommand($xcatrequest)
}
Function Set-NodeBoot {
    Param(
        [parameter(ValueFromPipeLine=$true)] $nodeRange,
        $bootDevice
    )
    $pipednr=@($input)
    if ($pipednr) { $nodeRange = $pipednr }
    $xcatrequest=@{'command'='rsetboot';'noderange'=$nodeRange;'args'=@($bootDevice)}
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
	$hashbyoutput=@{}
	foreach ($nodedata in $groupeddata) {
		$gdata= NewMergedxCATData $nodedata.Group
		if ($hashbyoutput.Contains($gdata.stringcontent)) {
			$hashbyoutput.Get_Item($gdata.stringcontent).NodeList += $gdata.NodeList
		} else {
			$hashbyoutput.Add($gdata.stringcontent,$gdata)
		}
	}
	$distinctoutput=$hashbyoutput.GetEnumerator()
	foreach ($collateddata in $distinctoutput) {
		$findata = $collateddata.Value
		$findata.NodeRange=[string]::Join(",",$findata.NodeList)
		$findata = $findata |select-object -excludeproperty NodeRangeHint,stringcontent *
		$mobjname = 'MergedxCATSimpleNodeData'
		foreach ($do in $findata.dataObjects) {
			if ($do.ErrorData) {
				$mobjname='MergedxCATNodeErrorData'
				break
			} elseif ($do.description) {
				$mobjname='MergedxCATNodeData'
				break
			}
		}
		foreach ($do in $findata.dataObjects) {
			$do|Add-Member -MemberType NoteProperty -Name NodeRange -Value $findata.NodeRange
			$do.PSObject.TypeNames.Insert(0,$mobjname)
			$do
		}
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
	if (!(ConnectxCAT)) { return }
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
				} elseif ($nr.PSObject.TypeNames[0] -like "xCAT*Node*Data") {
					$nrparts += $nr.Node
				} elseif ($nr.PSObject.TypeNames[0] -like "Merge*xCAT*Node*Data") {
					$nrparts += $nr.NodeRange
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
			NewxCATDataFromXmlElement $elem -NodeRangeHint $xcatRequest.noderange
		}
		foreach ($elem in $response.xcatresponse.error) {
			Write-Error $elem
		}
		#$response.xcatresponse.node.name
		#$response.xcatresponse.node.data
		if ($response.xcatresponse.serverdone -ne $null) { $serverdone=1 }
	}
}

Function NewMergedxCATData { #takes an arbitrary number of nodeData objects and spits out one
	Param(
		$nodeData
	)
	$myobj = @{}
	$myobj.dataObjects=@()
	$myobj.NodeList = @($nodeData[0].Node)
	$myobj.NodeRangeHint = $nodeData[0].NodeRangeHint
	$myobj.stringcontent = ""
	$myobj.NodeRange = ""
	foreach ($data in $nodeData) {
		$rangedata = $data|select-object -ExcludeProperty Node,NodeRangeHint *
		foreach ($dataseg in $rangedata) {
			if ($dataseg.ErrorData) { $myobj.stringcontent += "ERROR: "+$dataseg.ErrorData }
			$myobj.stringcontent += $dataseg.Description+": "+$dataseg.Data+"`n"
		}
		$myobj.dataObjects = $myobj.dataObjects  + $rangedata
	}
	$newobj = New-Object -TypeName PSObject -Prop $myobj
	$newobj.PSObject.TypeNames.Insert(0,'TempxCATNodeRangeData')
	return $newobj
}
Function NewxCATDataFromXmlElement {
	Param(
		$xmlElement,
		$NodeRangeHint
	)
	$myprops = @{}
	$objname = 'xCATSimpleNodeData'
	if ($NodeRangeHint) { #hypothetically, 'xcoll' implementation might find this handy
		$myprops.NodeRangeHint=$NodeRangeHint
	}
	if ($xmlElement.name) {
		$myprops.Node=$xmlElement.name
	}
    if ($xmlElement.data) {
        if ($xmlElement.data.GetType().Name -eq "String") {
            $myprops.Data=$xmlElement.data
        } else {
        	if ($xmlElement.data.desc) {
        		$objname = 'xCATNodeData'
        		$myprops.Description=$xmlElement.data.desc
        	}
        	if ($xmlElement.data.contents) {
        		$myprops.Data=$xmlElement.data.contents
        	} else {
        		$myprops.Data=""
    	    }
        }
    }
	if ($xmlElement.error) {
		$objname = 'xCATNodeErrorData'
		$errstr= $xmlElement.name + ": " + $xmlElement.error
		Write-Error $errstr
		$myprops.ErrorData=$xmlElement.error
	}
	$myobj=New-Object -TypeName PSObject -Prop $myprops
	$myobj.PSObject.TypeNames.Insert(0,$objname)
	return $myobj
}
New-Alias -name reventlog -value Get-NodeEventlog
New-Alias -name rsetboot -value Set-NodeBoot
New-Alias -name nodeset -value Set-NodeDeploy
New-Alias -name rpower -value Set-NodePower
New-Alias -name rvitals -value Get-Nodevitals
New-Alias -name rinv -value Get-NodeInventory
New-Alias -name rbeacon -value Set-NodeBeacon
New-Alias -name nodels -value Get-Nodes
New-Alias -name xcoll -value Merge-xCATData
Export-ModuleMember -function *-* -Alias *

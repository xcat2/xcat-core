<?php

// Display a wizard to assist the user in discovering new nodes

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/wizard.php";


// This array controls the order of pages in the wizard
$pages = array('intro' => 'Discover Hardware',
				'patterns' => 'Cluster Patterns',
				'patterns1b' => 'Switch Ports',
				'patterns2' => 'More Cluster Patterns',
				'preparemn' => 'Prepare Management Node',
				'prediscover' => 'Power On Hardware',
				'discover' => 'Discover HW Control Points',
				'updatedefs' => 'Update Definitions',
				'configurehcps' => 'Configure HW Control Points',
				'createnodes' => 'Create Nodes',
				/* 'testhcps' => 'Test HW Control', */
				'done' => 'Complete',
				);

if (isset($_REQUEST['page'])) {	displayWizard($pages); }

else {		// initial display of the wizard, show the whole page
insertHeader('Discover New Nodes', array('discover.css',"$TOPDIR/lib/wizard.css"), array("$TOPDIR/lib/wizard.js"), array('machines','discover'));
echo "<div id=content align=center>\n";
displayWizard($pages);
echo "</div>\n";	// end the content div
insertFooter();
}


//-----------------------------------------------------------------------------
// Save the values sent up from the previous wizard page into the session.
function savePostVars() {
foreach ($_POST as $k => $v) {
	if ($k != 'action' && $k != 'page') { $_SESSION[$k] = $v; }
	}
}


//-----------------------------------------------------------------------------
// Expand the noderange for non-existing nodes
function expandNR($nr) {
//todo: use xcatd to expand this.  Change xcatd around line 998: } elsif ($req->{command}->[0] eq "noderange" and $req->{noderange}) {
//		see pping as an example of the client/server for noderange expansion
$a = array();
if (empty($nr)) return $a;
if (strpos($nr,'-')===FALSE) { $a[] = $nr; return $a; }		// a single node
list($begin, $end) = explode('-', $nr);
$begParts = array();
if (!preg_match('/^(\D+)(\d+)$/', $begin, $begParts)) { msg('E',"Error in noderange syntax: $nr"); return NULL; }
$endParts = array();
if (!preg_match('/^(\D+)(\d+)$/', $end, $endParts)) { msg('E',"Error in noderange syntax: $nr"); return NULL; }
if ($begParts[1] != $endParts[1]) { msg('E',"Error in noderange syntax: $nr"); return NULL; }
$numlen = strlen($begParts[2]);
for ($i=$begParts[2]; $i<=$endParts[2]; $i++) {
	$istr = "$i";
	if (strlen($istr) < $numlen) { $istr = substr('000000',0,$numlen-strlen($istr)) . $istr; }
	$a[] = "$begParts[1]$istr";
	}
return $a;
}

//-----------------------------------------------------------------------------
function intro($action, $step) {
echo "<p>This wizard will guide you through the process of defining the naming conventions within your cluster, discovering the hardware on your network, and automatically defining it in the xCAT database.";
echo " Choose which type of hardware you want to discover, and then click Next.</p>\n";
// The least hacky way to get this list left justified, but have the block in the center, is to use a table.  CSS snobs, just deal with it.
echo "<form><table class=WizardListTable><tr><td><ul class=NoBullet>\n";
echo "<li><label class=Disabled><input type=radio name=hwType value=systemx disabled> System x hardware (not implemented yet)</label></li>\n";
echo "<li><label><input type=radio name=hwType value=systemp checked> System p hardware (only partially implemented)</label></li>\n";
echo "<p>&nbsp;<br><br><br><br></p>\n";
echo "</ul></td></tr></table></form>\n";
}


//-----------------------------------------------------------------------------
function patterns($action, $step) {
echo "<form><table cellpadding=5 cellspacing=0 class=WizardInputTable>\n";
echo "<tr><td colspan=5 class=Center><h3>Service LAN Switches</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=switchHostname>Hostname Range:</label></td><td class=Left><input type=text name=switchHostname id=switchHostname value='", @$_SESSION['switchHostname'], "'></td>\n";
echo "<td width=10></td><td class=Right><label for=switchIP>Starting IP Address:</label></td><td class=Left><input type=text name=switchIP id=switchIP value='", @$_SESSION['switchIP'], "'></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=portsPerSwitch>Number of Ports Per Switch:</label></td><td class=Left><input type=text name=portsPerSwitch id=portsPerSwitch value='", @$_SESSION['portsPerSwitch'], "'></td>\n";
echo "<td></td><td class=Right><label for=portPrefix>Switch Port Prefix:</label></td><td class=Left><input type=text name=portPrefix id=portPrefix value='", @$_SESSION["portPrefix"], "'></td></tr>\n";

echo "<tr><td colspan=5 class=Center><h3>HMCs</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=hmcHostname>Hostname Range:</label></td><td class=Left><input type=text name=hmcHostname id=hmcHostname value='", @$_SESSION['hmcHostname'], "'></td>\n";
echo "<td width=10></td><td class=Right><label for=hmcIP>Starting IP Address:</label></td><td class=Left><input type=text name=hmcIP id=hmcIP value='", @$_SESSION['hmcIP'], "'></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=numFramesPerHMC>Number of Frames per HMC:</label></td><td class=Left><input type=text name=numFramesPerHMC id=numFramesPerHMC value='", @$_SESSION['numFramesPerHMC'], "'></td><td></td><td></td><td></td></tr>\n";

echo "<tr><td colspan=5 class=Center><h3>Frames (BPAs)</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=bpaHostname>Hostname Range:</label></td><td class=Left><input type=text name=bpaHostname id=bpaHostname value='", @$_SESSION['bpaHostname'], "'></td>\n";
echo "<td width=10></td><td class=Right><label for=bpaIP>Starting IP Address:</label></td><td class=Left><input type=text name=bpaIP id=bpaIP value='", @$_SESSION['bpaIP'], "'></td></tr>\n";

echo "<tr><td colspan=5 class=Center><h3>Drawers (FSPs/CECs)</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=fspHostname>Hostname Range:</label></td><td class=Left><input type=text name=fspHostname id=fspHostname value='", @$_SESSION['fspHostname'], "'></td>\n";
echo "<td width=10></td><td class=Right><label for=fspIP>Starting IP Address:</label></td><td class=Left><input type=text name=fspIP id=fspIP value='", @$_SESSION['fspIP'], "'></td></tr>\n";

/*
echo "<tr><td colspan=2 class=Center><h3>Switch Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=switchHostname>Switch Hostname Pattern:</label></td><td class=Left><input type=text name=switchHostname id=switchHostname value='", @$_SESSION['switchHostname'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=switchIP>Switch IP Address Pattern:</label></td><td class=Left><input type=text name=switchIP id=switchIP value='", @$_SESSION['switchIP'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=portsPerSwitch>Number of Ports Per Switch:</label></td><td class=Left><input type=text name=portsPerSwitch id=portsPerSwitch value='", @$_SESSION['portsPerSwitch'], "'></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>HMCs</h3></td></tr>\n";
echo "<tr><td class=Right><label for=hmcHostname>HMC Hostname Pattern:</label></td><td class=Left><input type=text name=hmcHostname id=hmcHostname value='", @$_SESSION['hmcHostname'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=hmcIP>HMC IP Address Pattern:</label></td><td class=Left><input type=text name=hmcIP id=hmcIP value='", @$_SESSION['hmcIP'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=numCECs>Number of CECs per HMC:</label></td><td class=Left><input type=text name=numCECs id=numCECs value='", @$_SESSION['numCECs'], "'></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>Frame (BPA) Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=bpaHostname>BPA Hostname Pattern:</label></td><td class=Left><input type=text name=bpaHostname id=bpaHostname value='", @$_SESSION['bpaHostname'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=bpaIP>BPA IP Address Pattern:</label></td><td class=Left><input type=text name=bpaIP id=bpaIP value='", @$_SESSION['bpaIP'], "'></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>Drawer (FSP/CEC) Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=fspHostname>FSP Hostname Pattern:</label></td><td class=Left><input type=text name=fspHostname id=fspHostname value='", @$_SESSION['fspHostname'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=fspIP>FSP IP Address Pattern:</label></td><td class=Left><input type=text name=fspIP id=fspIP value='", @$_SESSION['fspIP'], "'></td></tr>\n";
*/

echo "</table></form>\n";

//todo: get HCP userids/pws from the user
}


//-----------------------------------------------------------------------------
function patterns1b($action, $step) {
//todo: do validation of all pages that have input
savePostVars();

// Figure out how many switches there need to be
$hmcs = expandNR($_SESSION['hmcHostname']);
$bpas = expandNR($_SESSION['bpaHostname']);
$fsps = expandNR($_SESSION['fspHostname']);
//echo "<p>", implode(',',$hmcs), "</p>\n";
$total = count($hmcs) + count($bpas) + count($fsps);
if (!$_SESSION['portsPerSwitch']) { $numswitches = 1; }
else { $numswitches = (integer) ((($total-1) / $_SESSION['portsPerSwitch']) + 1); }
//echo "<p>$numswitches</p>\n";

echo "<form><table cellpadding=5 cellspacing=0 class=WizardInputTable>\n";
echo "<tr><td colspan=2 class=Center><h3>Switch Port Assignments</h3></td></tr>\n";

$switches = expandNR($_SESSION['switchHostname']);
//todo: if count($switches) != $numswitches, then we have a problem
foreach ($switches as $k => $sw) {
	$num = $k + 1;
	echo "<tr class=WizardInputSection><td class=Right><label for=switchSequence$num>Switch Port Sequence for $sw:</label></td><td class=Left><input type=text name=switchSequence$num id=switchSequence$num value='", @$_SESSION["switchSequence$num"], "'></td></tr>\n";
	}

echo "<tr><td colspan=2 class=Center><h3>Discovery Information</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=dynamicIP>Dynamic IP Range for DHCP:</label></td><td class=Left><input type=text size=30 name=dynamicIP id=dynamicIP value='", @$_SESSION["dynamicIP"], "'></td></tr>\n";
echo "<p>&nbsp;<br></p>\n";
echo "</table></form>\n";
}


//-----------------------------------------------------------------------------
function patterns2($action, $step) {
savePostVars();
echo "<form><table cellpadding=5 cellspacing=0 class=WizardInputTable>\n";

// For now, many of the BB fields are disabled
echo "<tr><td colspan=2 class=Center><h3>Building Blocks</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=numFrames class=Disabled>Number of Frames per Building Block:</label></td><td class=Left><input type=text name=numFrames id=numFrames disabled></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=subnet>Starting Subnet IP for Cluster Mgmt LAN:</label></td><td class=Left><input type=text name=subnet id=subnet value='", @$_SESSION['subnet'], "'></td></tr>";
echo "<tr class=WizardInputSection><td colspan=2 class='Center Disabled'>(Subnet address for nodes in each Building Block)</td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=ioNodename class=Disabled>I/O Node Name Pattern:</label></td><td class=Left><input type=text name=ioNodename id=ioNodename disabled></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=computeNodename>Compute Node Hostname Range:</label></td><td class=Left><input type=text name=computeNodename id=computeNodename value='", @$_SESSION['computeNodename'], "'></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=hfiHostname class=Disabled>HFI NIC Hostname Range:</label></td><td class=Left><input type=text name=hfiHostname id=hfiHostname disabled></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=hfiIP class=Disabled>HFI NIC IP Address Range:</label></td><td class=Left><input type=text name=hfiIP id=hfiIP disabled></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>LPAR Information</h3></td></tr>\n";
echo "<tr class=WizardInputSection><td class=Right><label for=numLPARs>Number of LPARs per Drawer:</label></td><td class=Left><input type=text name=numLPARs id=numLPARs value='", @$_SESSION['numLPARs'], "'></td></tr>\n";
echo "</table></form>\n";
// do we need to get any info about the resources that should be in each lpar, or do we just divide them evenly?
}

//-----------------------------------------------------------------------------
function preparemn($action, $step) {
global $TOPDIR;

if ($step == 0) {
	savePostVars();
	insertProgressTable(array('Wrote xCAT switch table.',
								'Wrote xCAT hosts table.',
								'Defined networks.',
								'Configured DHCP.',
								));
	if ($action != 'back') { nextStep(1,FALSE); }
	}

elseif ($step == 1) { writeSwitchTable($step); }
elseif ($step == 2) { writeHostsTable($step); }
elseif ($step == 3) { setDynRange(@$_SESSION["dynamicIP"], $step); }
elseif ($step == 4) { makedhcp($step); }
}


//-----------------------------------------------------------------------------
// Using the hcp and switch ranges, write out the switch table
//todo: maybe should not use tabrestore in case we are just discovery additional hw
function writeSwitchTable($step) {
$hmcs = expandNR($_SESSION['hmcHostname']);
$bpas = expandNR($_SESSION['bpaHostname']);
$fsps = expandNR($_SESSION['fspHostname']);
$switches = expandNR($_SESSION['switchHostname']);
$numports = $_SESSION['portsPerSwitch'];
$data = array(array('#node,switch,port,vlan,interface,comments,disable'));
//echo "<p>\n";
foreach ($switches as $k => $sw) {
	$num = $k + 1;
	$sequence = $_SESSION["switchSequence$num"];
	$seq = preg_split('/[\s,]+/', $sequence);
	$port = 1;
	foreach ($seq as $s) {			// each $s is something like:  FSP:5
		list($type, $num) = explode(':', $s);
		if (preg_match('/^hmc$/i',$type)) $ar=&$hmcs;
		elseif (preg_match('/^bpa$/i',$type)) $ar=&$bpas;
		elseif (preg_match('/^fsp$/i',$type)) $ar=&$fsps;
		elseif (preg_match('/^space$/i',$type)) {if ($num=='*') {break;} $port+=$num; if ($port>$numports) break; else continue;}
		else { msg('E', "Invalid HW control point type in $s"); return; }
		if ($num == '*') { $num = count($ar); }
		for ($i=1; $i<=$num; $i++) {
			$node = array_shift($ar);
			$data[] = array($node,$sw,@$_SESSION['portPrefix'].$port);
			/* $xml = docmd('nodeadd',NULL,array($node,'groups=all',"switch.node=$node","switch.switch=$sw","switch.port=$port"));
			if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd failed: " . implode(' ',$errors)); return; }
			else { echo "Wrote: $node,$sw,$port<br>\n"; }*/
			if (++$port > $numports) break 2;
			}
		}
	}
//echo "</p>\n"; ob_flush(); flush();
//array_unshift($data, array('#node,switch,port,vlan,interface,comments,disable'));
$xml = doTabrestore('switch', $data);
if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore switch failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
// Using the hcp ranges, write out the hosts table
function writeHostsTable($step) {
$machines = array();
$machines[$_SESSION['switchIP']] = expandNR($_SESSION['switchHostname']);
$machines[$_SESSION['hmcIP']] = expandNR($_SESSION['hmcHostname']);
$machines[$_SESSION['bpaIP']] = expandNR($_SESSION['bpaHostname']);
$machines[$_SESSION['fspIP']] = expandNR($_SESSION['fspHostname']);
$machines[$_SESSION['subnet']] = expandNR($_SESSION['computeNodename']);
$data = array(array('#node,ip,hostnames,comments,disable'));
//echo "<p>\n";
foreach ($machines as $ip => $ar) {		// this loop goes thru each type of hw
	foreach ($ar as $hostname) {		// this loop goes thru each of the hostnames for that type of hw
		$data[] = array($hostname,$ip);
		//echo "<p class=WizardProgressOutput>Wrote: $hostname,$ip</p>\n"; ob_flush(); flush();
		//sleep(1);	// remove
		incrementIP($ip);
		}
	}
//echo "</p>\n"; ob_flush(); flush();
$xml = doTabrestore('hosts', $data);
if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore hosts failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
function incrementIP(& $ip) {

//todo: hard coded for the percs demo cluster - remove
if ($ip == '192.168.200.233') { $ip='192.168.200.237'; return; }
if ($ip == '192.168.200.237') { $ip='192.168.200.239'; return; }

$parts = explode('.', $ip);
$parts[3]++;
if ($parts[3] >= 255) {
	$parts[2]++; $parts[3] = 1;
	if ($parts[3] >= 255) { $parts[1]++; $parts[2] = 1; }		// assume parts[1] is not 255, because we never increment the 1st field
	}
$ip = implode('.', $parts);
}


//-----------------------------------------------------------------------------
//todo: we need a better way to change the networks table than tabdump/tabrestore.  We can not use chtab because its not client/svr.  We can not use chdef because there is no netname defined by makenetworks.
function setDynRange($range, $step) {

if (isset($range) && !empty($range)) {		// only set the dyn range if they entered it, otherwise another machine may be providing dynamic ranges
	// Get the whole table via tabdump
	$xml = docmd('tabdump','',array('networks'));
	if (getXmlErrors($xml,$errors)) { msg('E',"tabdump networks failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
	$data = array();
	foreach ($xml->children() as $response) foreach ($response->children() as $line) {
		$line = (string) $line;
		if(ereg("^#", $line)) {		// handle the header specially
			$data[] = array($line);
			continue;
			}
		$values = splitTableFields($line);
		//todo: only give the dynamic range to the network that has same ip as the dyn range
		$values[8] = '"' . $range . '"';		// dynamicrange is the 9th field
		$data[] = $values;
		}

	// Now restore that data back into the networks table
	$xml = doTabrestore('networks', $data);
	if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore networks failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
	}

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
function makedhcp($step) {
//todo: remove this check because we should always be running makedhcp, but it is starting dhcpd, which we do not want on the demo system
if (isset($_SESSION["dynamicIP"]) && !empty($_SESSION["dynamicIP"])) {
	$xml = docmd('makedhcp',NULL,array('-n'));
	if (getXmlErrors($xml,$errors)) { msg('E',"makedhcp failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
	}

//todo: also need to restart makedhcp so the omapi config takes hold

nextStep(++$step,TRUE);
}


//-----------------------------------------------------------------------------
function prediscover($action, $step) {
echo "<table class=WizardListTable><tr><td>\n";
echo "<p>Do the following manual steps now:</p>\n";
echo "<ol><li>Power on all of the HMCs.</li>\n";
echo "<li>Then power on all of frames.</li>\n";
echo "<li>Then click Next to discover the hardware on the service network.</li>\n";
echo "<p>&nbsp;<br><br><br><br></p>\n";
echo "</ol></td></tr></table>\n";
}


//-----------------------------------------------------------------------------
function discover($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array(array('Discovered HMCs, BPAs, and FSPs.','output')));
	if ($action != 'back') { nextStep(1,FALSE); }
	}

elseif ($step == 1) { lsslp($step); }
}


//-----------------------------------------------------------------------------
//todo: we are just simulating lsslp right now
function lsslp($step) {

$xml = docmd('nodeadd',NULL,array($_SESSION['hmcHostname'],'groups=hmc,all','nodetype.nodetype=hmc','nodehm.mgt=hmc'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd hmc failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
echo "<p class=WizardProgressOutput>Discovered and defined ", $_SESSION['hmcHostname'], ".</p>\n"; ob_flush(); flush();

$xml = docmd('nodeadd',NULL,array($_SESSION['bpaHostname'],'groups=frame,all','nodetype.nodetype=bpa','nodehm.mgt=hmc','nodehm.power=hmc','ppc.comments=bpa','vpd.mtm=9A00-100' /* ,'vpd.serial=|(\D+)(\d+)|($2)|' */ ));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd bpa failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
echo "<p class=WizardProgressOutput>Discovered and defined ", $_SESSION['bpaHostname'], ".</p>\n"; ob_flush(); flush();

$parts = array();
preg_match('/^(\D+)/', $_SESSION['bpaHostname'], $parts);
$bpaprefix = $parts[1];

// We are assuming there are 5 fsps in each bpa
//todo: when we use the real lsslp, it probably will not set nodepos attrs
$xml = docmd('nodeadd',NULL,array($_SESSION['fspHostname'],'groups=cec,all','nodetype.nodetype=fsp','nodehm.mgt=hmc','nodehm.power=hmc','ppc.id=|\D+(\d+)|((((($1-1)%5)+1)*2)-1)|','ppc.parent=|\D+(\d+)|'.$bpaprefix.'((($1-1)/5)+1)|','nodepos.u=|\D+(\d+)|((((($1-1)%5)+1)*2)-1)|','nodepos.rack=|\D+(\d+)|((($1-1)/5)+1)|','vpd.mtm=9125-F2A' /* ,'vpd.serial=|(\D+)(\d+)|($2)|' */ ));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd fsp failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
echo "<p class=WizardProgressOutput>Discovered and defined ", $_SESSION['fspHostname'], ".</p>\n"; ob_flush(); flush();

/*
$xml = docmd('chdef',NULL,array('-t','group','bpa','serial=|(\D+)(\d+)|($2)|','mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"chdef bpa failed: " . implode(' ',$errors)); return; }
$xml = docmd('chdef',NULL,array('-t','group','fsp','serial=|(\D+)(\d+)|($2)|','mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"chdef fsp failed: " . implode(' ',$errors)); return; }
*/

nextStep(++$step,TRUE);
}


//-----------------------------------------------------------------------------
function updatedefs($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array('Assigned frame numbers.',
								'Determined which CECs/Frames each HMC should manage.',
								'Created HW control point node groups.',
								/* 'Assigned supernode numbers and building block numbers.',
								'Assigned building block subnets.', */
								'Updated name resolution.',
								));
	if ($action != 'back') { nextStep(1,FALSE); }
	}

elseif ($step == 1) { assignframenums($step); }
elseif ($step == 2) { assigncecs($step); }
elseif ($step == 3) { createhcpgroups($step); }
elseif ($step == 4) { nameres($step); }
}


//-----------------------------------------------------------------------------
// Give frame numbers to each bpa
function assignframenums($step) {
//todo: this just uses the number from the nodename of the frame.  Should instead count from the beginning.
$xml = docmd('nodech','frame',array('ppc.id=|\D+(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodech frame failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
function assigncecs($step) {
$numFrames = $_SESSION['numFramesPerHMC'];
$hmcs = expandNR($_SESSION['hmcHostname']);
$bpas = expandNR($_SESSION['bpaHostname']);
$fsps = expandNR($_SESSION['fspHostname']);

// 1st query ppc.parent of all fsps and save in a hash, so we can assign the bpa and its fsps to the
// same hmc.
$fspparent = getNodes($_SESSION['fspHostname'], array('ppc.parent'));
$bpacecs = array();
foreach ($fspparent as $fsp => $parent) { $bpacecs[$parent][] = $fsp; }

$h = 0;		// start with the 1st hmc
$b = 0;
// Go thru the bpas taking groups of numFrames and assigning them to the next hmc
while (TRUE) {
	// Get the next group of fsps
	$length = min($numFrames, count($bpas)-$b);
	$bslice = array_slice($bpas, $b, $length);

	// Assign the bpa to the hmc
	//trace("b=$b, numFrames=$numFrames, length=$length.");
	//echo "<p>bpas:"; print_r($bpas); "</p>\n";
	//trace("nodech ".implode(',',$bslice));
	$xml = docmd('nodech',implode(',',$bslice),array("ppc.hcp=$hmcs[$h]","ppc.parent=$hmcs[$h]"));
	if (getXmlErrors($xml,$errors)) { msg('E',"nodech bpa failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

	// Collect the list of the fsps in these bpas
	$fsprange = array();
	foreach ($bslice as $b2) { $fsprange = array_merge($fsprange, $bpacecs[$b2]); }
	//trace("nodech ".implode(',',$fsprange));
	$xml = docmd('nodech',implode(',',$fsprange),array("ppc.hcp=$hmcs[$h]"));
	if (getXmlErrors($xml,$errors)) { msg('E',"nodech fsp failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

	// Decide if we are all out of bpas
	$h++;
	$b += $length;
	if ($h>=count($hmcs) || $b>=count($bpas)) break;
	}

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
function createhcpgroups($step) {
//todo: may need to do this once we are using the real lsslp

nextStep(++$step,FALSE);
}


//-----------------------------------------------------------------------------
// Run makehosts and makedns
function nameres($step) {
$xml = docmd('makehosts',NULL,NULL);
if (getXmlErrors($xml,$errors)) { msg('E',"makehosts failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
$xml = docmd('makedns',NULL,NULL);
if (getXmlErrors($xml,$errors)) { msg('E',"makedns failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }

nextStep(++$step,TRUE);
}


//-----------------------------------------------------------------------------
function configurehcps($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array(array('Assigned CECs to their HMC.','disabled'),
								array('Set frame numbers in BPAs.','disabled'),
								array('Powered on CECs to Standby.','disabled'),
								));
	if ($action != 'back') { nextStep(1,FALSE); }
	}

elseif ($step == 1) { cecs2hmcs($step); }
elseif ($step == 2) { setframenum($step); }
elseif ($step == 3) { cecs2standby($step); }

//todo: set HCP userids/pws
}

function cecs2hmcs($step) {nextStep(++$step,FALSE);}
function setframenum($step) {nextStep(++$step,FALSE);}
function cecs2standby($step) {nextStep(++$step,TRUE);}


//-----------------------------------------------------------------------------
function createnodes($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array(array('Created LPARs in each CEC and save node definitions in xCAT database.','output')));
	if ($action != 'back') { nextStep(1,FALSE); }
	}

elseif ($step == 1) { createlpars($step); }
//todo: set up rcons for the lpars (makeconserver.cf)
}


//-----------------------------------------------------------------------------
function createlpars($step) {
$numlpars = $_SESSION['numLPARs'];
$fsps = expandNR($_SESSION['fspHostname']);
$nodes = expandNR($_SESSION['computeNodename']);
$n = 0;		// index into the nodes array
//$parts = array();
//preg_match('/^(\D+)/', $_SESSION['fspHostname'], $parts);
//$fspprefix = $parts[1];
$fspattrs = getNodes($_SESSION['fspHostname'], array('ppc.hcp','ppc.parent'));

// Go thru each fsp and create/define the nodes that should be in that fsp
foreach ($fsps as $f) {
	$length = min($numlpars, count($nodes)-$n);
	$hcp = $fspattrs[$f]['ppc.hcp'];
	$bpa = $fspattrs[$f]['ppc.parent'];

	//todo: currently can not create the 1st lpar in the cec
	$xml = docmd('nodeadd',NULL,array($nodes[$n],"groups=lpars-$f,lpars-$bpa,lpars-$hcp,lpar,all",'nodetype.nodetype=lpar,osi',
								'nodehm.mgt=hmc','nodehm.power=hmc','nodehm.cons=hmc','noderes.netboot=yaboot',
								'nodetype.arch=ppc64','ppc.id=3',
								"ppc.parent=$f","ppc.hcp=$hcp",'ppc.pprofile=diskless2'));
	if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd nodes failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
	echo "<p class=WizardProgressOutput>Created and defined $nodes[$n] in $f.</p>\n"; ob_flush(); flush();
	$length--; $n++;

	$nmax = $length + $n;
	$numnodes = 5;		// how many lpars to create before displaying some output
	$n2 = $n;

	// Go thru $length nodes, $numnodes at a time, creating the lpars and defining the nodes in the db
	while (TRUE) {
		$length2 = min($numnodes, $nmax-$n2);
		$nslice = array_slice($nodes, $n2, $length2);
		$nstr = implode(',',$nslice);

		//todo: this assumes the lpar id starts at 3 for a cec
		$xml = docmd('nodeadd',NULL,array($nstr,"groups=lpars-$f,lpars-$bpa,lpars-$hcp,lpar,all",'nodetype.nodetype=lpar,osi',
								'nodehm.mgt=hmc','nodehm.power=hmc','nodehm.cons=hmc','noderes.netboot=yaboot',
								'nodetype.arch=ppc64','ppc.id=|\D+(\d+)|((($1-1)%'.$numlpars.')+3)|',
								"ppc.parent=$f","ppc.hcp=$hcp",'ppc.pprofile=diskless2'));
		if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd nodes failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
		// Actually make the lpar profiles.  Todo: this is not actually creating the lpar, just a new profile for the existing lpars.
		if ($_SERVER["SERVER_ADDR"] != '192.168.153.128') {		//todo: remove this check
			$xml = docmd('chvm',$nstr,array('-p','diskless2'));
			if (getXmlErrors($xml,$errors)) { msg('E',"chvm failed for $nstr: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
			}
		echo "<p class=WizardProgressOutput>Created and defined $nstr in $f.</p>\n"; ob_flush(); flush();

		$n2 += $length2;
		if ($n2 >= $nmax) break;
		}

	// Decide if we are all out of nodes
	$n += $length;
	if ($n >= count($nodes)) break;
	}

//		Also, the following assumes the node range starts with 1 and the fsp node range is simple.
//		Really need to do individual nodeadd for each node.
/*
$xml = docmd('nodeadd',NULL,array($_SESSION['computeNodename'],'groups=lpar,all','nodetype.nodetype=lpar,osi',
								'nodehm.mgt=hmc','nodehm.power=hmc','nodehm.cons=hmc','noderes.netboot=yaboot',
								'nodetype.arch=ppc64','ppc.id=|\D+(\d+)|((($1-1)%'.$numlpars.')+1)|',
								'ppc.parent=|(\D+)(\d+)|'.$fspprefix.'((($2-1)/'.$numlpars.')+1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd nodes failed: " . implode(' ',$errors)); nextStep(++$step,TRUE); return; }
*/

nextStep(++$step,TRUE);
}



//-----------------------------------------------------------------------------
// Currently not used.
function testhcps($action, $step) {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img id=chk src='$TOPDIR/images/unchecked-box.gif'>(Output for rpower stat for sample nodes)</li>\n";
echo "<li><img id=chk src='$TOPDIR/images/unchecked-box.gif'>(Output for rinv for sample nodes)</li>\n";
echo "<li><img id=chk src='$TOPDIR/images/unchecked-box.gif'>(Output for rvitals for sample nodes)</li>\n";
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
function done($action, $step) {
global $TOPDIR;
echo "<p id=wizardDone>Cluster set up successfully completed!</p>\n";
echo "<p>You can now <a href='$TOPDIR/machines/groups.php'>view your node definitions</a> and start to <a href='$TOPDIR/deploy/osimages.php'>deploy nodes</a>.</p>\n";
echo "<p>&nbsp;<br><br><br><br></p>\n";
}
?>
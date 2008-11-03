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
echo "</ul></td></tr></table></form>\n";
}


//-----------------------------------------------------------------------------
function patterns($action, $step) {
echo "<form><table cellspacing=5>\n";
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

echo "<form><table cellspacing=5>\n";
echo "<tr><td colspan=2 class=Center><h3>Switch Port Assignments</h3></td></tr>\n";

$switches = expandNR($_SESSION['switchHostname']);
//todo: if count($switches) != $numswitches, then we have a problem
foreach ($switches as $k => $sw) {
	$num = $k + 1;
	echo "<tr><td class=Right><label for=switchSequence$num>Switch Port Sequence for $sw:</label></td><td class=Left><input type=text name=switchSequence$num id=switchSequence$num value='", @$_SESSION["switchSequence$num"], "'></td></tr>\n";
	}

echo "<tr><td colspan=2 class=Center><h3>Discovery Information</h3></td></tr>\n";
echo "<tr><td class=Right><label for=dynamicIP>Dynamic IP Range for DHCP:</label></td><td class=Left><input type=text size=30 name=dynamicIP id=dynamicIP value='", @$_SESSION["dynamicIP"], "'></td></tr>\n";
echo "</table></form>\n";
}


//-----------------------------------------------------------------------------
function patterns2($action, $step) {
savePostVars();
echo "<form><table cellspacing=5>\n";

// For now, many of the BB fields are disabled
echo "<tr><td colspan=2 class=Center><h3 class=Disabled>Building Blocks</h3></td></tr>\n";
echo "<tr><td class=Right><label for=numFrames class=Disabled>Number of Frames per Building Block:</label></td><td class=Left><input type=text name=numFrames id=numFrames disabled></td></tr>\n";
echo "<tr><td class=Right><label for=subnet>Subnet Pattern for Cluster Mgmt LAN:</label></td><td class=Left><input type=text name=subnet id=subnet value='", @$_SESSION['subnet'], "'></td></tr>";
echo "<tr><td colspan=2 class='Center Disabled'>(Subnet address for nodes in each Building Block)</td></tr>\n";
echo "<tr><td class=Right><label for=ioNodename class=Disabled>I/O Node Name Pattern:</label></td><td class=Left><input type=text name=ioNodename id=ioNodename disabled></td></tr>\n";
echo "<tr><td class=Right><label for=computeNodename>Compute Node Name Pattern:</label></td><td class=Left><input type=text name=computeNodename id=computeNodename value='", @$_SESSION['computeNodename'], "'></td></tr>\n";
echo "<tr><td class=Right><label for=hfiHostname class=Disabled>HFI NIC Hostname Pattern:</label></td><td class=Left><input type=text name=hfiHostname id=hfiHostname disabled></td></tr>\n";
echo "<tr><td class=Right><label for=hfiIP class=Disabled>HFI NIC IP Address Pattern:</label></td><td class=Left><input type=text name=hfiIP id=hfiIP disabled></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>LPAR Information</h3></td></tr>\n";
echo "<tr><td class=Right><label for=numLPARs>Number of LPARs per Drawer:</label></td><td class=Left><input type=text name=numLPARs id=numLPARs value='", @$_SESSION['numLPARs'], "'></td></tr>\n";
echo "</table></form>\n";
// do we need to get any info about the resources that should be in each lpar, or do we just divide them evenly?
}

//-----------------------------------------------------------------------------
function preparemn($action, $step) {
global $TOPDIR;

if ($step == 0) {
	savePostVars();
	insertProgressTable(array('Write xCAT switch table.',
								'Write xCAT hosts table.',
								'Define networks.',
								'Configure DHCP.',
								));
	if ($action != 'back') { echo "<script type='text/javascript'>wizardStep(1,false,'');</script>"; }
	}

elseif ($step == 1) { writeSwitchTable($step); }
elseif ($step == 2) { writeHostsTable($step); }
elseif ($step == 3) { setDynRange($_SESSION["dynamicIP"], $step); }
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
		else { msg('E', "Invalid HW control point type in $s"); return; }
		if ($num == '*') { $num = count($ar); }
		for ($i=1; $i<=$num; $i++) {
			$node = array_shift($ar);
			$data[] = array($node,$sw,$port);
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
//$errors = array();
if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore switch failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
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
		//echo "Wrote: $hostname,$ip<br>\n";
		incrementIP($ip);
		}
	}
//echo "</p>\n"; ob_flush(); flush();
$xml = doTabrestore('hosts', $data);
$errors = array();
if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore hosts failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function incrementIP(& $ip) {
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
// Get the whole table via tabdump
$xml = docmd('tabdump','',array('networks'));
$data = array();
foreach ($xml->children() as $response) foreach ($response->children() as $line) {
	$line = (string) $line;
	if(ereg("^#", $line)) {		// handle the header specially
		$data[] = array($line);
		continue;
		}
	$values = splitTableFields($line);
	$values[8] = '"' . $range . '"';		// dynamicrange is the 9th field
	$data[] = $values;
	}

// Now restore that data back into the networks table
$xml = doTabrestore('networks', $data);
$errors = array();
if (getXmlErrors($xml,$errors)) { msg('E',"tabrestore networks failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function makedhcp($step) {
$xml = docmd('makedhcp',NULL,array('-n'));
$errors = array();
if (getXmlErrors($xml,$errors)) { msg('E',"makedhcp failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => TRUE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function prediscover($action, $step) {
echo "<table class=WizardListTable><tr><td>\n";
echo "<p>Do the following manual steps now:</p>\n";
echo "<ol><li>Power on all of the HMCs.</li>\n";
echo "<li>Then power on all of frames.</li>\n";
echo "<li>Then click Next to discover the hardware on the service network.</li>\n";
echo "</ol></td></tr></table>\n";
}


//-----------------------------------------------------------------------------
function discover($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array('Discover HMCs, BPAs, and FSPs.'));
	if ($action != 'back') { echo "<script type='text/javascript'>wizardStep(1,false,'');</script>"; }
	}

elseif ($step == 1) { lsslp($step); }
}


//-----------------------------------------------------------------------------
//todo: we are just simulating lsslp right now
function lsslp($step) {
/* todo: show this
echo "<p>";
echo "Discovered HMCs: ", $_SESSION['hmcHostname'], "<br>\n";
echo "Discovered BPAs: ", $_SESSION['bpaHostname'], "<br>\n";
echo "Discovered FSPs: ", $_SESSION['fspHostname'], "<br>\n";
echo "</p>\n";
*/

//$errors = array();
$xml = docmd('nodeadd',NULL,array($_SESSION['hmcHostname'],'groups=hmc,all','nodetype.nodetype=hmc'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd hmc failed: " . implode(' ',$errors)); return; }

$xml = docmd('nodeadd',NULL,array($_SESSION['bpaHostname'],'groups=bpa,all','nodetype.nodetype=bpa','nodehm.mgt=hmc','nodehm.power=hmc','ppc.comments=bpa','vpd.serial=|(\D+)(\d+)|($2)|','vpd.mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd bpa failed: " . implode(' ',$errors)); return; }

// We are assuming there are 4 fsps in each bpa
$xml = docmd('nodeadd',NULL,array($_SESSION['fspHostname'],'groups=fsp,all','nodetype.nodetype=fsp','nodehm.mgt=hmc','nodehm.power=hmc','ppc.id=|\D+(\d+)|((($1-1)%4)+1)|','ppc.parent=|(\D+)(\d+)|b((($2-1)/4)+1)|','vpd.serial=|(\D+)(\d+)|($2)|','vpd.mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd fsp failed: " . implode(' ',$errors)); return; }

/*
$xml = docmd('chdef',NULL,array('-t','group','bpa','serial=|(\D+)(\d+)|($2)|','mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"chdef bpa failed: " . implode(' ',$errors)); return; }
$xml = docmd('chdef',NULL,array('-t','group','fsp','serial=|(\D+)(\d+)|($2)|','mtm=|(\D+)(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"chdef fsp failed: " . implode(' ',$errors)); return; }
*/

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => TRUE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function updatedefs($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array('Determine which CECs each HMC should manage.',
								'Create HW control point node groups.',
								'Assign frame numbers.',
								/* 'Assign supernode numbers and building block numbers.',
								'Assign building block subnets.', */
								'Update name resolution.',
								));
	if ($action != 'back') { echo "<script type='text/javascript'>wizardStep(1,false,'');</script>"; }
	}

elseif ($step == 1) { assigncecs($step); }
elseif ($step == 2) { createhcpgroups($step); }
elseif ($step == 3) { assignframenums($step); }
elseif ($step == 4) { nameres($step); }
}


//-----------------------------------------------------------------------------
function assigncecs($step) {
$numCECs = $_SESSION['numCECs'];
$hmcs = expandNR($_SESSION['hmcHostname']);
$bpas = expandNR($_SESSION['bpaHostname']);
$fsps = expandNR($_SESSION['fspHostname']);
$h = 0;		// start with the 1st hmc
$f = 0;
$errors = array();
// Go thru the fsps taking groups of numCECs and assigning them to the next hmc
while (TRUE) {
	// Get the next group of fsps
	$length = min($numCECs, count($fsps)-$f);
	$fslice = array_slice($fsps, $f, $length);
	$xml = docmd('nodech',implode(',',$fslice),array("ppc.hcp=$hmcs[$h]"));
	if (getXmlErrors($xml,$errors)) { msg('E',"nodech fsp failed: " . implode(' ',$errors)); return; }

	// Decide if we are all out of fsps
	$h++;
	$f += $length;
	if ($h>=count($hmcs) || $f>=count($fsps)) break;
	}
//todo: how do we decide what bpas to assign to which hmcs?

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function createhcpgroups($step) {
//todo: may need to do this once we are using the real lsslp

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
}


//-----------------------------------------------------------------------------
// Give frame numbers to each bpa
function assignframenums($step) {
$errors = array();
$xml = docmd('nodech','bpa',array('ppc.id=|\D+(\d+)|($1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodech bpa failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));
}


//-----------------------------------------------------------------------------
// Run makehosts and makedns
function nameres($step) {
$errors = array();
$xml = docmd('makehosts',NULL,NULL);
if (getXmlErrors($xml,$errors)) { msg('E',"makehosts failed: " . implode(' ',$errors)); return; }
$xml = docmd('makedns',NULL,NULL);
if (getXmlErrors($xml,$errors)) { msg('E',"makedns failed: " . implode(' ',$errors)); return; }

// Send JSON data back to the browser.  Todo: handle the errors too.
echo json_encode(array('step' => (integer)++$step, 'done' => TRUE, 'error' => ''));
}


//-----------------------------------------------------------------------------
function configurehcps($action, $step) {
global $TOPDIR;
if ($step == 0) {
	insertProgressTable(array('Assign CECs to their HMC.',
								'Set frame numbers in BPAs.',
								'Power on CECs to Standby.',
								));
	if ($action != 'back') { echo "<script type='text/javascript'>wizardStep(1,false,'');</script>"; }
	}

elseif ($step == 1) { cecs2hmcs($step); }
elseif ($step == 2) { setframenum($step); }
elseif ($step == 3) { cecs2standby($step); }

//todo: set HCP userids/pws
}

function cecs2hmcs($step) {echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));}
function setframenum($step) {echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));}
function cecs2standby($step) {echo json_encode(array('step' => (integer)++$step, 'done' => TRUE, 'error' => ''));}


//-----------------------------------------------------------------------------
function createnodes($action, $step) {
global $TOPDIR;
//todo: need to show progress for each CEC
if ($step == 0) {
	insertProgressTable(array('Create LPARs in each CEC and save node definitions in xCAT database.'));
	if ($action != 'back') { echo "<script type='text/javascript'>wizardStep(1,false,'');</script>"; }
	}

elseif ($step == 1) { createlpars($step); }
}


//-----------------------------------------------------------------------------
function createlpars($step) {
$numlpars = $_SESSION['numLPARs'];
$fsps = expandNR($_SESSION['fspHostname']);
$nodes = expandNR($_SESSION['computeNodename']);
$samplenode = '';		//todo:  ???
$errors = array();
$n = 0;		// index into the nodes array
foreach ($fsps as $f) {
	$length = min($numlpars, count($nodes)-$n);
	$nslice = array_slice($nodes, $n, $length);
	//todo: actually make the lpars
	//$xml = docmd('mkvm',NULL,array($samplenode,'-i','1','-n',implode(',',$nslice)));
	//if (getXmlErrors($xml,$errors)) { msg('E',"mkvm failed: " . implode(' ',$errors)); return; }

	// Decide if we are all out of nodes
	$n += $length;
	if ($n >= count($nodes)) break;
	}

//todo: Change this when mkvm is creating the base node definition.
//		Also, the following assumes the node range starts with 1 and the fsp node range is simple.
//		Really need to do individual nodeadd for each node.
$parts = array();
preg_match('/^(\D+)/', $_SESSION['fspHostname'], $parts);
$fsp = $parts[1];
$xml = docmd('nodeadd',NULL,array($_SESSION['computeNodename'],'groups=lpar,all','nodetype.nodetype=lpar,osi',
								'nodehm.mgt=hmc','nodehm.power=hmc','nodehm.cons=hmc','noderes.netboot=yaboot',
								'nodetype.arch=ppc64','ppc.id=|\D+(\d+)|((($1-1)%'.$numlpars.')+1)|',
								'ppc.parent=|(\D+)(\d+)|'.$fsp.'((($2-1)/'.$numlpars.')+1)|'));
if (getXmlErrors($xml,$errors)) { msg('E',"nodeadd nodes failed: " . implode(' ',$errors)); return; }

echo json_encode(array('step' => (integer)++$step, 'done' => TRUE, 'error' => ''));
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
}
?>
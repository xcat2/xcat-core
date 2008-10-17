<?php

// Display a wizard to assist the user in discovering new nodes

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/wizard.php";


// This array controls the order of pages in the wizard
$pages = array('intro' => 'Discover Hardware',
				'patterns' => 'Cluster Patterns',
				'patterns2' => 'More Cluster Patterns',
				'preparemn' => 'Prepare Management Node',
				'prediscover' => 'Power On Hardware',
				'discover' => 'Discover HW Control Points',
				'updatedefs' => 'Update Definitions',
				'configurehcps' => 'Configure HW Control Points',
				'createnodes' => 'Create Nodes',
				'testhcps' => 'Test HW Control',
				'done' => 'Complete',
				);

if (isset($_REQUEST['page'])) {	displayWizard($pages); }

else {		// initial display of the wizard, show the whole page
insertHeader('Discover New Nodes', array('discover.css',"$TOPDIR/lib/wizard.css"), array("$TOPDIR/jq/jquery.min.js"), array('machines','discover'));
echo "<div id=content align=center>\n";
displayWizard($pages);
echo "</div>\n";	// end the content div
insertFooter();
}


//-----------------------------------------------------------------------------
function intro() {
echo "<p>This wizard will guide you through the process of defining the naming conventions within your cluster, discovering the hardware on your network, and automatically defining it in the xCAT database.";
echo " Choose which type of hardware you want to discover, and then click Next.</p>\n";
echo "<table cellspacing=5>\n";
echo "<tr><td align=left><label><input type=radio name=hwType value=systemx disabled> System x hardware (not implemented yet)</label></td></tr>\n";
echo "<tr><td align=left><label><input type=radio name=hwType value=systemp checked> System p hardware</label></td></tr>\n";
echo "</table>\n";
}


//-----------------------------------------------------------------------------
function patterns() {
echo "<table cellspacing=5>\n";
echo "<tr><td colspan=2 align=center><h3>Switch Patterns</h3></td></tr>\n";
echo "<tr><td align=right><label for=switchHostname>Switch Hostname Pattern:</label></td><td align=left><input type=text name=switchHostname id=switchHostname></td></tr>\n";
echo "<tr><td align=right><label for=switchIP>Switch IP Address Pattern:</label></td><td align=left><input type=text name=switchIP id=switchIP></td></tr>\n";

echo "<tr><td colspan=2 align=center><h3>HMCs</h3></td></tr>\n";
echo "<tr><td align=right><label for=hmcHostname>HMC Hostname Pattern:</label></td><td align=left><input type=text name=hmcHostname id=hmcHostname></td></tr>\n";
echo "<tr><td align=right><label for=hmcIP>HMC IP Address Pattern:</label></td><td align=left><input type=text name=hmcIP id=hmcIP></td></tr>\n";
echo "<tr><td align=right><label for=numCECs>Number of CECs per HMC:</label></td><td align=left><input type=text name=numCECs id=numCECs></td></tr>\n";

echo "<tr><td colspan=2 align=center><h3>Frame (BPA) Patterns</h3></td></tr>\n";
echo "<tr><td align=right><label for=bpaHostname>BPA Hostname Pattern:</label></td><td align=left><input type=text name=bpaHostname id=bpaHostname></td></tr>\n";
echo "<tr><td align=right><label for=bpaIP>BPA IP Address Pattern:</label></td><td align=left><input type=text name=bpaIP id=bpaIP></td></tr>\n";

echo "<tr><td colspan=2 align=center><h3>Drawer (FSP/CEC) Patterns</h3></td></tr>\n";
echo "<tr><td align=right><label for=fspHostname>FSP Hostname Pattern:</label></td><td align=left><input type=text name=fspHostname id=fspHostname></td></tr>\n";
echo "<tr><td align=right><label for=fspIP>FSP IP Address Pattern:</label></td><td align=left><input type=text name=fspIP id=fspIP></td></tr>\n";
echo "</table>\n";

//todo: get HCP userids/pws
}


//-----------------------------------------------------------------------------
function patterns2() {
echo "<table cellspacing=5>\n";
echo "<tr><td colspan=2 align=center><h3>Building Blocks</h3></td></tr>\n";
echo "<tr><td align=right><label for=numFrames>Number of Frames per Building Block:</label></td><td align=left><input type=text name=numFrames id=numFrames></td></tr>\n";
echo "<tr><td align=right><label for=subnet>Subnet Pattern for Cluster Mgmt LAN:</label></td><td align=left><input type=text name=subnet id=subnet></td></tr>";
echo "<tr><td colspan=2 align=center>(Subnet address in each Building Block)</td></tr>\n";
echo "<tr><td align=right><label for=ioNodename>I/O Node Name Pattern:</label></td><td align=left><input type=text name=ioNodename id=ioNodename></td></tr>\n";
echo "<tr><td align=right><label for=computeNodename>Compute Node Name Pattern:</label></td><td align=left><input type=text name=computeNodename id=computeNodename></td></tr>\n";
echo "<tr><td align=right><label for=hfiHostname>HFI NIC Hostname Pattern:</label></td><td align=left><input type=text name=hfiHostname id=hfiHostname></td></tr>\n";
echo "<tr><td align=right><label for=hfiIP>HFI NIC IP Address Pattern:</label></td><td align=left><input type=text name=hfiIP id=hfiIP></td></tr>\n";

echo "<tr><td colspan=2 align=center><h3>LPAR Information</h3></td></tr>\n";
echo "<tr><td align=right><label for=numLPARs>Number of LPARs per Drawer:</label></td><td align=left><input type=text name=numLPARs id=numLPARs></td></tr>\n";
echo "</table>\n";
// do we need to get any info about the resources that should be in each lpar, or do we just divide them evenly?
}


//-----------------------------------------------------------------------------
function preparemn() {
global $TOPDIR;
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Write Cluster Topology Configuration File.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Define networks.</td></tr>\n";	// run makenetworks and update the dynamic range for the service LAN
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Configure DHCP.</td></tr>\n";	// run makedhcp and show progress
echo "</table>\n";
}


//-----------------------------------------------------------------------------
function prediscover() {
//todo: there's a better way to get this list left justified, but have the block in the center, but don't feel like figuring it out right now.
echo "<table><tr><td align=left>\n";
echo "<ol><li>Power on all of the HMCs.<li>Then power on all of frames.<li>Then click Next to discover the hardware on the service network.</ol>\n";
echo "</td></tr></table>\n";
}


//-----------------------------------------------------------------------------
function discover() {
global $TOPDIR;
//todo: run lsslp and show progress
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Discovering HMCs, BPAs, and FSPs...</td></tr>\n";
echo "</table>\n";
echo "<p>(This will show the list of hw discovered & located, including nodenames and IP addresses assigned, and then save all info to the DB.)</p>\n";
}


//-----------------------------------------------------------------------------
function updatedefs() {
global $TOPDIR;
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Determine which CECs each HMC should manage.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Assign frame numbers, supernode numbers, and building block numbers.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Assign building block subnets.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Update name resolution.</td></tr>\n";	// run makedhosts and makedns
echo "</table>\n";
}


//-----------------------------------------------------------------------------
function configurehcps() {
global $TOPDIR;
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Assign CECs to their HMC.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Set frame numbers in BPAs.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Power on CECs to Standby.</td></tr>\n";
echo "</table>\n";

//todo: set HCP userids/pws
}


//-----------------------------------------------------------------------------
function createnodes() {
global $TOPDIR;
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Create LPARs in each CEC.</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>Save node definitions in xCAT database.</td></tr>\n";
echo "</table>\n";
}


//-----------------------------------------------------------------------------
function testhcps() {
global $TOPDIR;
echo "<table class=wizardProgressTable border=0 cellspacing=10>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>(Output for rpower stat for sample nodes)</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>(Output for rinv for sample nodes)</td></tr>\n";
echo "<tr><td><img src='$TOPDIR/images/checked-box.gif'></td><td>(Output for rvitals for sample nodes)</td></tr>\n";
echo "</table>\n";
}


//-----------------------------------------------------------------------------
function done() {
global $TOPDIR;
echo "<p id=wizardDone>Cluster set up successfully completed!</p>\n";
echo "<p>You can now start to <a href='$TOPDIR/deploy/osimages.php'>deploy nodes</a>.</p>\n";
}
?>
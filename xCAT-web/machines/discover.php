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
// The least hacky way to get this list left justified, but have the block in the center, is to use a table.  CSS snobs, just deal with it.
echo "<table class=WizardListTable><tr><td><ul class=NoBullet>\n";
echo "<li><label><input type=radio name=hwType value=systemx disabled> System x hardware (not implemented yet)</label></li>\n";
echo "<li><label><input type=radio name=hwType value=systemp checked> System p hardware</label></li>\n";
echo "</ul></td></tr></table>\n";
}


//-----------------------------------------------------------------------------
function patterns() {
echo "<table cellspacing=5>\n";
echo "<tr><td colspan=2 class=Center><h3>Switch Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=switchHostname>Switch Hostname Pattern:</label></td><td class=Left><input type=text name=switchHostname id=switchHostname></td></tr>\n";
echo "<tr><td class=Right><label for=switchIP>Switch IP Address Pattern:</label></td><td class=Left><input type=text name=switchIP id=switchIP></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>HMCs</h3></td></tr>\n";
echo "<tr><td class=Right><label for=hmcHostname>HMC Hostname Pattern:</label></td><td class=Left><input type=text name=hmcHostname id=hmcHostname></td></tr>\n";
echo "<tr><td class=Right><label for=hmcIP>HMC IP Address Pattern:</label></td><td class=Left><input type=text name=hmcIP id=hmcIP></td></tr>\n";
echo "<tr><td class=Right><label for=numCECs>Number of CECs per HMC:</label></td><td class=Left><input type=text name=numCECs id=numCECs></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>Frame (BPA) Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=bpaHostname>BPA Hostname Pattern:</label></td><td class=Left><input type=text name=bpaHostname id=bpaHostname></td></tr>\n";
echo "<tr><td class=Right><label for=bpaIP>BPA IP Address Pattern:</label></td><td class=Left><input type=text name=bpaIP id=bpaIP></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>Drawer (FSP/CEC) Patterns</h3></td></tr>\n";
echo "<tr><td class=Right><label for=fspHostname>FSP Hostname Pattern:</label></td><td class=Left><input type=text name=fspHostname id=fspHostname></td></tr>\n";
echo "<tr><td class=Right><label for=fspIP>FSP IP Address Pattern:</label></td><td class=Left><input type=text name=fspIP id=fspIP></td></tr>\n";
echo "</table>\n";

//todo: get HCP userids/pws from the user
}


//-----------------------------------------------------------------------------
function patterns2() {
echo "<table cellspacing=5>\n";
echo "<tr><td colspan=2 class=Center><h3>Building Blocks</h3></td></tr>\n";
echo "<tr><td class=Right><label for=numFrames>Number of Frames per Building Block:</label></td><td class=Left><input type=text name=numFrames id=numFrames></td></tr>\n";
echo "<tr><td class=Right><label for=subnet>Subnet Pattern for Cluster Mgmt LAN:</label></td><td class=Left><input type=text name=subnet id=subnet></td></tr>";
echo "<tr><td colspan=2 class=Center>(Subnet address in each Building Block)</td></tr>\n";
echo "<tr><td class=Right><label for=ioNodename>I/O Node Name Pattern:</label></td><td class=Left><input type=text name=ioNodename id=ioNodename></td></tr>\n";
echo "<tr><td class=Right><label for=computeNodename>Compute Node Name Pattern:</label></td><td class=Left><input type=text name=computeNodename id=computeNodename></td></tr>\n";
echo "<tr><td class=Right><label for=hfiHostname>HFI NIC Hostname Pattern:</label></td><td class=Left><input type=text name=hfiHostname id=hfiHostname></td></tr>\n";
echo "<tr><td class=Right><label for=hfiIP>HFI NIC IP Address Pattern:</label></td><td class=Left><input type=text name=hfiIP id=hfiIP></td></tr>\n";

echo "<tr><td colspan=2 class=Center><h3>LPAR Information</h3></td></tr>\n";
echo "<tr><td class=Right><label for=numLPARs>Number of LPARs per Drawer:</label></td><td class=Left><input type=text name=numLPARs id=numLPARs></td></tr>\n";
echo "</table>\n";
// do we need to get any info about the resources that should be in each lpar, or do we just divide them evenly?
}


//-----------------------------------------------------------------------------
function preparemn() {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Write Cluster Topology Configuration File.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Define networks.</li>\n";	// run makenetworks and update the dynamic range for the service LAN
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Configure DHCP.</li>\n";	// run makedhcp and show progress
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
function prediscover() {
echo "<table class=WizardListTable><tr><td>\n";
echo "<p>Do the following manual steps now:</p>\n";
echo "<ol><li>Power on all of the HMCs.</li>\n";
echo "<li>Then power on all of frames.</li>\n";
echo "<li>Then click Next to discover the hardware on the service network.</li>\n";
echo "</ol></td></tr></table>\n";
}


//-----------------------------------------------------------------------------
function discover() {
global $TOPDIR;
//todo: run lsslp and show progress
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Discovering HMCs, BPAs, and FSPs...</li>\n";
echo "</ul></table>\n";
echo "<p>(This will show the list of hw discovered & located, including nodenames and IP addresses assigned, and then save all info to the DB.)</p>\n";
}


//-----------------------------------------------------------------------------
function updatedefs() {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Determine which CECs each HMC should manage.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Assign frame numbers, supernode numbers, and building block numbers.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Assign building block subnets.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Update name resolution.</li>\n";	// run makedhosts and makedns
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
function configurehcps() {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Assign CECs to their HMC.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Set frame numbers in BPAs.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Power on CECs to Standby.</li>\n";
echo "</ul></table>\n";

//todo: set HCP userids/pws
}


//-----------------------------------------------------------------------------
function createnodes() {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Create LPARs in each CEC.</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>Save node definitions in xCAT database.</li>\n";
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
function testhcps() {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>(Output for rpower stat for sample nodes)</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>(Output for rinv for sample nodes)</li>\n";
echo "<li><img src='$TOPDIR/images/checked-box.gif'>(Output for rvitals for sample nodes)</li>\n";
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
function done() {
global $TOPDIR;
echo "<p id=wizardDone>Cluster set up successfully completed!</p>\n";
echo "<p>You can now <a href='$TOPDIR/machines/groups.php'>view your node definitions</a> and start to <a href='$TOPDIR/deploy/osimages.php'>deploy nodes</a>.</p>\n";
}
?>
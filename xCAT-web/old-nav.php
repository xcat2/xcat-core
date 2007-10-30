<?php

// This file is no longer used...

/*------------------------------------------------------------------------------
   Create the navigation area on the left.
   $currentlink is the key of the link to the page
   that is currently being displayed.
------------------------------------------------------------------------------*/

function insertNav($currentLink) {
// A few constants
global $TOPDIR;    // or could use $GLOBALS['TOPDIR']
$colTxt = "Click to collapse section";
$exTxt = "Click to expand section";
$bulgif = "$TOPDIR/images/h3bg_new.gif";
$minusgif = "$TOPDIR/images/minus-sign.gif";
$plusgif = "$TOPDIR/images/plus-sign.gif";

echo '<div id=nav><table border="0" cellpadding="0" cellspacing="1" width="110">';

//Console section
insertInner('open', 1,'Console', 'constab', $currentLink, array(
	'prefs' => array("$TOPDIR/prefs.php", 'Preferences'),
	'updategui' => array("$TOPDIR/softmaint/updategui.php", 'Update'),
	'suggestions' => array("$TOPDIR/suggestions.html", 'Suggestions'),
	'logout' => array("$TOPDIR/logout.php", 'Logout')
));

// xCAT Cluster section
?>
 <TR><TD id="menu_level1" width="110">
 <P title="<?php echo $colTxt; ?>" onclick="toggleSection(this,'clustab')" ondblclick="toggleSection(this,'clustab')">
 <IMG src=<?php echo $minusgif ?> id='clustab-im'> xCAT Cluster
 </P></TD></TR>
 <TR><TD>
  <TABLE id='clustab' cellpadding=0 cellspacing=0 width="110"><TBODY>
    <TR><TD id="menu_level2"><A href="csmconfig">Settings</A></TD></TR>

<?php
	insertInner('open', 2,'Installation', 'installtab', $currentLink, array(
		'softmaint' => array("$TOPDIR/softmaint", 'MS Software'),
		'addnodes' => array("$TOPDIR/addnodes.php", 'Add Nodes'),
		'definenode' => array("$TOPDIR/definenode.php", 'Define Nodes'),
		'hwctrl' => array("$TOPDIR/hwctrl/index.php", 'HW Control')
	));
	insertInner('open', 2,'Administration', 'admintab', $currentLink, array(
		'nodes' => array("$TOPDIR/index.php", 'Nodes'),
		'layout' => array("$TOPDIR/hwctrl/layout.php", 'Layout'),
		'dsh' => array("$TOPDIR/dsh.php", 'Run Cmds'),
		'dcp' => array("$TOPDIR/dcp.php", 'Copy Files'),
		'cfm' => array("$TOPDIR/cfm.php", 'Sync Files'),
		'shell' => array("$TOPDIR/shell.php", 'Cmd on MS'),
		'import' => array("$TOPDIR/import.php", 'Import/Export'),
	));
	insertInner('open', 2,'Monitor', 'montab', $currentLink, array(
		'conditions' => array("$TOPDIR/mon", 'Conditions'),
		'responses' => array("$TOPDIR/mon/resp.php", 'Responses'),
		'sensors' => array("$TOPDIR/mon/sensor.php", 'Sensors'),
		'rmcclass' => array("$TOPDIR/mon/rmcclass.php", 'RMC Classes'),
		'auditlog' => array("$TOPDIR/mon/auditlog.php", 'Event Log'),
		'perfmon' => array("$TOPDIR/perfmon/index.php", 'Performance'),

	));
	insertInner('open', 2,'Diagnostics', 'diagtab', $currentLink, array(
		'diagms' => array("$TOPDIR/diagms", 'MS Diags'),
	));

  echo '</TABLE></TD></TR>';

insertInner('open', 1,'Documentation', 'doctab', $currentLink, array(
	'xcatdocs' => array(getDocURL('web','docs'), 'xCAT Docs'),
	'forum' => array(getDocURL('web','forum'), 'Mailing List'),
	'codeupdates' => array(getDocURL('web','updates'), 'Code Updates'),
	'opensrc' => array(getDocURL('web','opensrc'), 'Open Src Reqs'),
	'wiki' => array(getDocURL('web','wiki'), 'xCAT Wiki'),
));

echo '</table></div>';
}  //end insertNav
?>



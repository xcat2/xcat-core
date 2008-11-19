<?php

// Main page of the xCAT web interface

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
if (isAIX()) { $aixDisabled = 'disabled'; }

insertHeader('xCAT Groups and Nodes', array("$TOPDIR/jq/jsTree/tree_component.css",'groups.css','attributes.css',"$TOPDIR/manage/dsh.css"),
	array("$TOPDIR/jq/jsTree/css.js","$TOPDIR/jq/jsTree/jquery.listen.js","$TOPDIR/jq/jsTree/tree_component.js","$TOPDIR/jq/jquery.cookie.js",'noderangetree.js','groups.js','attributes.js','rvitals.js'),
	array('machines','groups'));

echo "<div id=content>\n";

// Create the noderange tree and the tabs side by side.  Once again I tried to do this with css and all
// methods seemed to be inadequate
echo "<table cellspacing=0 cellpadding=0><tr valign=top>\n";
echo "<td><div id=nrtree></div></td>\n";		// nrtree is the place to put the noderange tree

$tabs = array('Attributes' => '#attributes-tab',
				'Run Cmd' => '../manage/dsh.php?intab=1',
				'Rvitals' => '#rvitals-tab',
				);
$tabsDisabled = array('Rpower' => 'rpower.php',
				'Ping' => 'ping.php',
				'Copy' => 'copyfiles.php',
				'SP Config' => 'spconfig.php',
				'Diagnose' => 'diagnode.php',
				'Add/Remove' => 'addremove.php',
			);

echo "<td width='100%'><div id=nodetabs>\n";

echo "<ul>\n";
foreach ($tabs as $key => $url) {
	echo "<li class='ui-tabs-nav-item'><a id='nodetabs-a' href='$url'>$key</a></li>\n";
}
foreach ($tabsDisabled as $key2 => $url2) {
	echo "<li class='ui-tabs-nav-item'><a id='nodetabs-a-disabled' href='$url2'>$key2</a></li>\n";
}
echo "</ul>\n";
echo "<div id='attributes-tab'></div>\n";
echo "<div id='rvitals-tab'></div>\n";

echo "</div></td></tr></table>\n";

//echo "<div id=placeHolder></div>\n";	// since the other 2 divs are floats, need this one to give the content div some size


/*
echo '<table><tr>';
echo '<td><img src="' . getStatusImage('good') . '"> Good</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('warning') . '"> Possible problem</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('bad') . '"> Problem</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('unknown') . '"> Unknown</td>';
echo '</tr></table>';
*/

echo '</div>';		// end the content div
insertFooter();



//-----------------------------------------------------------------------------
// Returns the aggregate status of each node group in the cluster.  The return value is a
// hash in which the key is the group name and the value is nodelist.status.
function getGroupStatus() {
	$groups = array();
	$xml = docmd('tabdump','',array('nodelist'));
	foreach ($xml->children() as $response) foreach ($response->children() as $line) {
		$line = (string) $line;
		//echo "<p>"; print_r($line); "</p>\n";
		if (ereg("^#", $line)) { continue; }	// skip the header
		$vals = splitTableFields($line);
		if (empty($vals[0]) || empty($vals[1])) continue;	// node or groups missing
		$grplist = preg_split('/,/', $vals[1]);
		if (empty($vals[2])) { $status = 'unknown'; }
		else { $status = $vals[2]; }
		foreach ($grplist as $g) {
			if (array_key_exists($g,$groups)) { $groups[$g] = minStatus($groups[$g], $status); }
			else { $groups[$g] = $status; }
		}
	}
	return $groups;
}


?>
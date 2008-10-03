<?php

// Main page of the xCAT web interface

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
if (isAIX()) { $aixDisabled = 'disabled'; }

require_once("$TOPDIR/lib/GroupNodeTable.class.php");

insertHeader('xCAT Groups and Nodes', array('groups.css'),
	array("$TOPDIR/lib/GroupNodeTableUpdater.js","$TOPDIR/js/prototype.js","$TOPDIR/js/scriptaculous.js?load=effects"),
	array('machines','groups'));

echo "<div id=content align=center>\n";

insertButtons(
		array('label' => 'Attributes', 'onclick' => ''),
		array('label' => 'Create Group', 'onclick' => ''),
		array('label' => 'Ping', 'onclick' => ''),
		//'Updatenode',
		array('label' => 'Run Cmd', 'onclick' => ''),
		array('label' => 'Copy Files', 'onclick' => ''),
		array('label' => 'Sync Files', 'onclick' => '')
	);
insertButtons(
		//'Soft Maint',
		array('label' => 'HW Ctrl', 'onclick' => ''),
		array('label' => 'RSA/MM/FSP', 'onclick' => ''),
		array('label' => 'Deploy', 'onclick' => ''),
		array('label' => 'Diagnose', 'onclick' => ''),
		array('label' => 'Remove', 'onclick' => '')
	);
	/*
	array(
		'name=propButton value="Attributes"',
		'name=defineButton value="Create Like"',
		'name=createGroupButton value="Create Group"',
		'name=pingNodesButton value="Ping"',
		//'name=updateButton value="Updatenode"',
		'name=runcmdButton value="Run Cmd"',
		'name=copyFilesButton value="Copy Files"'
	),
	array(
		//'name=softMaintButton value="Soft Maint" onclick="this.form.nodesNeeded=1;"',
		'name=hwctrlButton value="HW Ctrl"',
		'name=rsaButton value="RSA/MM/FSP" onclick="this.form.nodesNeeded=1;"',
		'name=installButton value="Install"',
		'name=perfmonButton value="Perf Mon"',
		//'name=webminButton value="Webmin" onclick="this.form.nodesNeeded=1;"',
		'name=diagButton value="Diagnose" onclick="this.form.nodesNeeded=1;"',
		'name=removeButton value="Remove"'
	),
	*/

echo '<form name="nodelist" class=ContentForm>';

GroupNodeTable::insertGroupTableHeader();

// Get the names and status of the groups
$groups = getGroupStatus();

// Print the HTML for each of them
foreach($groups as $group => $status) {
	//echo "<p>$group status is $status</p>";
	echo GroupNodeTable::insertGroupTableRow($group, $status);
}

GroupNodeTable::insertGroupTableFooter();

echo '<!-- <SCRIPT language="JavaScript"> XCATEvent.doExpandNodes(); </SCRIPT> --></form><table><tr>';

echo '<td><img src="' . getStatusImage('good') . '"> Good</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('warning') . '"> Possible problem</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('bad') . '"> Problem</td><td width=20></td>';
echo '<td><img src="' . getStatusImage('unknown') . '"> Unknown</td>';

echo '</tr></table></div>';
insertFooter();



//-----------------------------------------------------------------------------
// Returns the aggregate status of each node group in the cluster.  The return value is a
// hash in which the key is the group name and the value is nodelist.status.
function getGroupStatus() {
	$groups = array();
	$xml = docmd('tabdump','',array('nodelist'));
	$output = $xml->xcatresponse->children();
	#$output = $xml->children();	// technically, we should iterate over the xcatresponses, because there can be more than one
	foreach ($output as $line) {
		//echo "<p>line=$line</p>";
		$vals = array();
		preg_match('/^"([^"]*)","([^"]*)",(.*)$/', $line, $vals);	//todo: create function to parse tabdump output better
		if (count($vals) > 3) {
			//$node = $vals[1];
			$grplist = preg_split('/,/', $vals[2]);
			$rest = $vals[3];
			$status = array();
			preg_match('/^"([^"]*)"/', $rest, $status);
			if (count($status) < 2) { $status[1] = 'unknown'; }
			foreach ($grplist as $g) {
				if (array_key_exists($g,$groups)) { $groups[$g] = minStatus($groups[$g], $status[1]); }
				else { $groups[$g] = $status[1]; }
			}
		}
	}
	return $groups;
}


?>
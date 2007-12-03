<?php

// Main page of the xCAT web interface

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
if (isAIX()) { $aixDisabled = 'disabled'; }

require_once("$TOPDIR/lib/GroupNodeTable.class.php");

insertHeader('Groups', array('groups.css'),
	array("$TOPDIR/lib/GroupNodeTableUpdater.js","$TOPDIR/js/prototype.js","$TOPDIR/js/scriptaculous.js?load=effects"),
	array('machines','groups'));

echo "<div id=content align=center>\n";

insertButtons(array(
	array(
		'Attributes',
		'Create Group',
		'Ping',
		//'Updatenode',
		'Run Cmd',
		'Copy Files',
		'Sync Files'
	),
	array(
		//'Soft Maint',
		'HW Ctrl',
		'RSA/MM/FSP',
		'Deploy',
		'Diagnose',
		'Remove'
	),
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
));

echo '<form name="nodelist" class=ContentForm>';

/* $output = array(); runcmd("/bin/sudo listattr", 2, $output); foreach ($output as $line) { echo "<p>line=$line</p>"; } */

GroupNodeTable::insertGroupTableHeader();

// Get the names and status of the groups
$groups = getGroupStatus();

// Print the HTML for each of them
foreach($groups as $group => $status) {
	//echo "<p>$group status is $status</p>";
	echo GroupNodeTable::insertGroupTableRow($group, $status);
}

GroupNodeTable::insertGroupTableFooter();

echo <<<EOS
<!-- <SCRIPT language="JavaScript"> XCATEvent.doExpandNodes(); </SCRIPT> -->
</form>
<table>
<tr><td><img src="$TOPDIR/images/green-ball-m.gif"></td><td align=left>Node is good (Status is ready/pbs/sshd)</td></tr>
<tr><td><img src="$TOPDIR/images/red-ball-m.gif"></td><td align=left>Node is bad (Status is 'noping')</td></tr>
<tr><td><img src="$TOPDIR/images/yellow-ball-m.gif"></td><td align=left>Other status (unknown/node unavailable...)</td></tr>
</table>
<p id=disclaimer>This interface is still under construction and not yet ready for use.</p>
</div>
</BODY>
</HTML>
EOS;
?>
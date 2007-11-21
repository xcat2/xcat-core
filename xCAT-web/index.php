<?php

// Main page of the xCAT web interface

$TOPDIR = '.';
require_once "$TOPDIR/functions.php";
if (isAIX()) { $aixDisabled = 'disabled'; }

require_once("lib/GroupNodeTable.class.php");
require_once("lib/XCAT/XCATCommand/XCATCommandRunner.class.php");

insertHeader('Nodes', NULL, NULL, array('machines','nodes'));

echo "<div id=content align=center>\n";

insertButtons(array(
	array(
		'Attributes',
		'Create Like',
		'Create Group',
		'Ping',
		//'Updatenode',
		'Run Cmd',
		'Copy Files'
	),
	array(
		//'Soft Maint',
		'HW Ctrl',
		'RSA/MM/FSP',
		'Install',
		'Perf Mon',
		//'Webmin',
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

/* $output = array(); runcmd("\bin\sudo listattr", 2, $output); foreach ($output as $line) { echo "<p>line=$line</p>"; } */

GroupNodeTable::insertGroupTableHeader();

// Get all the names of the groups
$xcmdr = new XCATCommandRunner();
$nodeGroupNames = $xcmdr->getAllXCATGroups();

// Print the HTML for each of them
foreach($nodeGroupNames as $key => $nodeGroupName) {
	echo GroupNodeTable::insertGroupTableRow($nodeGroupName);
}

GroupNodeTable::insertGroupTableFooter();

echo <<<EOS
<!-- <SCRIPT language="JavaScript"> XCATEvent.doExpandNodes(); </SCRIPT> -->
</form>
<table>
<tr>
  <td><img src="images/green-ball-m.gif"></td>
  <td align=left>Node is good (Status is ready/pbs/sshd)</td>
</tr>
<tr>
  <td><img src="images/red-ball-m.gif"></td>
  <td align=left>Node is bad (Status is 'noping')</td>
</tr>
<tr>
  <td><img src="images/yellow-ball-m.gif"></td>
  <td align=left>Other status (unknown/node unavailable...)</td>
</tr>
</table>
<p id=disclaimer>This interface is still under construction and not yet ready for use.</p>
</div>
</BODY>
</HTML>
EOS;
?>
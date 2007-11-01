<?php

// Main page of the xCAT web interface

$TOPDIR = '.';
require_once "$TOPDIR/functions.php";
//require_once "$TOPDIR/nav.php";
if (isAIX()) { $aixDisabled = 'disabled'; }

//require_once("globalconfig.php");
require_once("lib/XCAT/HTML/HTMLProducer.class.php");
require_once("lib/XCAT/XCATCommand/XCATCommandRunner.class.php");


insertHeader('Nodes', NULL, NULL);
insertNav('nodes');

echo "<div id=content align=center> <h1 class=PageHeading>Cluster Groups and Nodes</h1>";


insertButtons(array(
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
));

echo '<br><form name="nodelist">';

/*
$output = array();
runcmd("\bin\sudo listattr", 2, $output);
foreach ($output as $line) { echo "<p>line=$line</p>"; }
*/

echo HTMLProducer::getXCATNodeTableHeader();

// Get all the names of the groups
$xcmdr = new XCATCommandRunner();
//$nodeGroupNames = $xcmdr->getAllGroupNames();
$nodeGroupNames = $xcmdr->getAllXCATGroups();

// Print the HTML for each of them
foreach($nodeGroupNames as $key => $nodeGroupName) {
	echo HTMLProducer::getXCATGroupTableRow($nodeGroupName);
}

echo HTMLProducer::getXCATNodeTableFooter();
?>
<script type="text/javascript" src="js_xcat/event.js"> </script>
<script type="text/javascript" src="js_xcat/ui.js"> </script>
<SCRIPT language="JavaScript">
<!--
	XCATEvent.doExpandNodes();
-->
</SCRIPT>
</form>
<br>
<table>
<tr>
  <td><div align="center"><img src="images/green-ball-m.gif"></div></td>
  <td>Node is good (Status is  ready/pbs/sshd)</td>
</tr>
<tr>
  <td><div align="center"><img src="images/red-ball-m.gif"></div></td>
  <td>Node is bad (Status is 'noping')</td>
</tr>
<tr>
  <td><div align="center"><img src="images/yellow-ball-m.gif"></div></td>
  <td>Other status (unknown/node unavailable...)</td>
</tr>
</table>
</div>
</BODY>
</HTML>
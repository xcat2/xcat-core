<?php

// Main page of the xCAT web interface

$TOPDIR = '.';
require_once "$TOPDIR/functions.php";
//require_once "$TOPDIR/nav.php";

//require_once("globalconfig.php");
require_once("lib/XCAT/HTML/HTMLProducer.class.php");
require_once("lib/XCAT/XCATCommand/XCATCommandRunner.class.php");


insertHeader('Nodes', NULL, NULL);
insertNav('nodes');
if (isAIX()) { $aixDisabled = 'disabled'; }
?>
<div id=content align=center>
<h1 class=PageHeading>Cluster Groups and Nodes</h1>
<table border=0 cellspacing=0>
  <tr class="BlueBack">
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Attribute</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Define Like</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Create Group</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Ping</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Update</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Run Cmd</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#">Copy Files</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC"><div align="center"><a href="#"></a></div></td>
  </tr>
  <tr>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Soft Maint</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">HW Ctrl</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">RSA/MM/FSP</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Install</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Perf Mon</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Webmin</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Diagnose</a></div></td>
    <td width="90" height="20" background="images/baractive2.gif" bgcolor="#CCCCCC" class="BlueBack"><div align="center"><a href="#">Remove</a></div></td>
  </tr>
</table>
<br>
<form name="nodelist">
<?php

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
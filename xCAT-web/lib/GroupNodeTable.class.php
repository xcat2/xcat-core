<?php
/**
 * Produces HTML for use in the interface.
 */
if (!$TOPDIR) { $TOPDIR = '..'; }
require_once "$TOPDIR/lib/functions.php";

class GroupNodeTable {


function GroupNodeTable() {}

/**
 * @return A string containing the HTML for the header of the table.
 */
function insertGroupTableHeader() {
echo <<<EOS
<table border="0" cellspacing="1" cellpadding=1>
<tr class=TableHeader>
	<td width="88" align=left><input type="checkbox" name="chk_node_all" id="chk_node_all">Groups</td>
	<td>Status</td><td>Comment</td>
</tr>

EOS;
	return;
}

function insertGroupTableFooter() {
	echo "</table>";
	return;
}

/**
 * @param String nodeGroupName		The name of the node group.
 */
function getToggleString($nodeGroupName) {
global $TOPDIR;
//$colTxt = "Click to collapse section";
$exTxt = "Click to expand section";
//$bulgif = "$TOPDIR/images/h3bg_new.gif";
//$minusgif = "$TOPDIR/images/minus-sign.gif";
$plusgif = "$TOPDIR/images/plus-sign.gif";

	$html = <<<EOS
<span
	title="$exTxt"
	id="img_gr_$nodeGroupName"
	onclick="GroupNodeTableUpdater.updateNodeList('$nodeGroupName')"
	ondblclick="toggleSection(this,'div_$nodeGroupName')">
	<img src="$plusgif" id="div_$nodeGroupName-im" name="div_$nodeGroupName-im">
EOS;

	return $html;
}

/**
 * @param String nodeGroup	The group.
 */
function insertGroupTableRow($nodeGroupName, $status) {
$img_string = getStatusImage(GroupNodeTable::determineStatus($status));

//echo '<tr bgcolor="#FFCC00"><td align=left>';
echo '<tr class=TableRow><td align=left width=140>';
echo GroupNodeTable::getToggleString($nodeGroupName);
echo <<<EOE
	<input type="checkbox" name="chk_node_group_$nodeGroupName"  id="chk_node_group_$nodeGroupName"><b>$nodeGroupName</b></span>
	</td>
	<td align=center><img src="$img_string"></td>
	<td>&nbsp;</td>
	</tr>
	<tr><td colspan=3><div id=div_$nodeGroupName style="display:none"></div></td></tr>
EOE;
return;
}

// This is used by nodes_by_group.php
	/**
	 * @param An array of node groups, each of which contains an array of attr/value pairs
	 * returns the table that contains all the nodes information of that group
	 */
function getNodeGroupSection($group, $nodes) {
	global $TOPDIR;
	$imagedir = "$TOPDIR/images";
	$right_arrow_gif = $imagedir . "/grey_arrow_r.gif";
	$left_arrow_gif = $imagedir . "/grey_arrow_l.gif";

	$html .= "<table id='$group' class=GroupNodeTable width='100%' cellpadding=0 cellspacing=1 border=0>\n";
	$html .= "<TR class=GroupNodeTableHeader><TD>Node Name</TD><TD>Arch</TD><TD>OS</TD><TD>Mode</TD><TD>Status</TD><TD>Power Method</TD><TD>Comment</TD></TR>\n";

	foreach($nodes as $nodeName => $attrs) {
		$html .= GroupNodeTable::getNodeTableRow($nodeName, $attrs);
	}

	$html .= "<TR class=GroupNodeTableRow><TD colspan=9 align=right><image src='$left_arrow_gif' alt='Previous page'>&nbsp;&nbsp;&nbsp;&nbsp;<image src='$right_arrow_gif' alt='Next page'>&nbsp;&nbsp;</TD></TR>\n";
	$html .= "</table>\n";

	return $html;
}

	/**
	 * @param The node for which we want to generate the html.
	 */
function getNodeTableRow($nodeName, $attrs) {
	$html = "<tr class=GroupNodeTableRow>\n" .
			"<td align=left><input type=checkbox name='node_$nodeName' >$nodeName</td>\n" .
			"<td>" . $attrs['arch'] . "</td>\n" .
			"<td>" . $attrs['osversion'] . "</td>\n" .
			"<td>" . $attrs['mode'] . "</td>\n";

	$stat = 'unknown';   //todo: implement
	$img_string = '<img src="' . getStatusImage($stat) . '">';

	$html .= "<td>" . $img_string . "</td>".
			"<td>" . $attrs['power'] . "</td>".
			"<td>" . $attrs['comment'] . "</td></tr>";

	return $html;
	}

/**
 * @param String nodestatStr	The status of the node as output by the nodestat command
 * @return "good", "bad", "warning", or "unknown"
 */
function determineStatus($statStr) {
	$status = NULL;
	if ($statStr == "ready" || $statStr == "pbs" || $statStr == "sshd") { $status = "good"; }
	else if ($statStr == "noping") { $status = "bad"; }
	else if ($statStr == "ping") { $status = "warning"; }
	else { $status = "unknown"; }
	return $status;
}

}   // end the class
?>

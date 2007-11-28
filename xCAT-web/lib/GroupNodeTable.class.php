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
	<td>HW Type</td><td>OS</td><td>Mode</td><td>Status</td><td>HW Ctrl Pt</td><td>Comment</td>
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
	onclick="XCATui.updateNodeList('$nodeGroupName')"
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
echo '<tr class=TableRow><td align=left>';
echo GroupNodeTable::getToggleString($nodeGroupName);
echo <<<EOE
	<input type="checkbox" name="chk_node_group_$nodeGroupName"  id="chk_node_group_$nodeGroupName"><b>$nodeGroupName</b></span>
	</td>
	<td>&nbsp;</td>
	<td>&nbsp;</td>
	<td>&nbsp;</td>
	<td><img src="$img_string"></td>
	<td>&nbsp;</td>
	<td>&nbsp;</td>
	</tr>
	<tr style="display:none"><td colspan=7><div id=div_$nodeGroupName style="display:none"></div></td></tr>
EOE;
return;
}

// This is used by nodes_by_group.php
	/**
	 * @param XCATNodeGroup	nodeGroup	The node group for which we want to generate the html.
	 * returns the table that contains all the nodes information of that group
	 */
function getNodeGroupSection($nodeGroup) {
		$imagedir = 'images';
		$right_arrow_gif = $imagedir . "/grey_arrow_r.gif";
		$left_arrow_gif = $imagedir . "/grey_arrow_l.gif";

		$html .= <<<EOS
		<table id="
EOS;
		$html .= $nodeGroup->getName();
		$html .= <<<EOS
				" width='100%' cellpadding=0 cellspacing=1 border=0>
EOS;

		$nodes = $nodeGroup->getNodes();

		foreach($nodes as $nodeName => $node) {
			$html .= GroupNodeTable::getNodeTableRow($node);
		}

		$html .= "<TR bgcolor=\"#FFFF66\"><TD colspan=9 align=\"right\"><image src=\"$left_arrow_gif\" alt=\"Previous page\">&nbsp;&nbsp;&nbsp;&nbsp;<image src=\"$right_arrow_gif\" alt=\"Next page\">&nbsp;&nbsp;</TD></TR>";
		$html .= <<<EOS
		</table>
EOS;

	return $html;
}

	/**
	 * @param XCATNode	node	The node for which we want to generate the html.
	 */
function getNodeTableRow($node) {

		$imagedir = 'images';

		//echo $node->getName();
		$html = "<tr bgcolor=\"#FFFF66\" class=\"indent\">
				<td width=89><input type=\"checkbox\" name=\"node_" .$node->getName(). "\" />" .$node->getName(). "</td>" .
				"<td width=38><div align=center>" . $node->getHwType(). "</div></td>".
				"<td width=22><div align=center>" . $node->getOs(). "</div></td>".
				"<td width=43><div align=center>" . $node->getMode(). "</div></td>";

		$stat = $node->getStatus();
		$img_string = '<img src="' . getStatusImage($stat) . '">';

		$html .= "<td width=43><div align=center>" . $img_string . "</div></td>".
				"<td width=85><div align=center>" . $node->getHwCtrlPt(). "</div></td>".
				"<td width=71><div align=center>" . $node->getComment(). "</div></td></tr>";

EOS;
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

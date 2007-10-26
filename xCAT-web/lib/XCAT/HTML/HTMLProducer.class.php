<?php
/**
 * Produces HTML for use in the interface.
 */
require_once("config.php");

class HTMLProducer {


function HTMLProducer() {}

/**
 * @return A string containing the HTML for the header of the table.
 */
function getXCATNodeTableHeader() {
$html = <<<EOS
<table width="483" border="0" cellspacing="1" cellpadding=0>
<tr bgcolor="#C2CEDE" class="BlueBack">
	<td width="88">
		<div align="center">
			<input type="checkbox" name="chk_node_all" id="chk_node_all" />
			Nodes
		</div>
	</td>
	<td width="40"><div align="center">HW Type</div></td>
	<td width="25"><div align="center">OS</div></td>
	<td width="46"><div align="center">Mode</div></td>
	<td width="47"><div align="center">Status</div></td>
	<td width="89"><div align="center">HW Ctrl Pt</div></td>
	<td width="74"><div align="center">Comment</div></td>
	</tr>
EOS;

	return $html;
}

function getXCATNodeTableFooter() {
$html = <<<EOS
</table>
EOS;
	return $html;
}

/**
 * @param String nodeGroupName		The name of the node group.
 */
function getToggleString($nodeGroupName) {
	global $imagedir;
	global $colTxt, $exTxt;
	global $bulgif;
	global $minusgif;
	global $plusgif;
	$html = <<<EOS
<span
	title="Click to expand section"
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
function getXCATGroupTableRow($nodeGroup) {

$config = &Config::getInstance();
$imagedir = $config->getValue("IMAGEDIR");
$nodeGroupName = $nodeGroup->getName();
$img_string = XCATNodeGroupUtil::getImageString($nodeGroup->getStatus());

$html = <<<EOS
<tr bgcolor="#FFCC00">
	<td>
EOS;
		$html .= HTMLProducer::getToggleString($nodeGroupName);
		$html .= <<<EOE
<input type="checkbox" name="chk_node_group_$nodeGroupName"  id="chk_node_group_$nodeGroupName"><b>$nodeGroupName</b></span>
	</td>
	<td><div align="center">&nbsp;</div></td>
	<td><div align="center">&nbsp;</div></td>
	<td><div align="center">&nbsp;</div></td>
	<td><div align="center">$img_string</div></td>
	<td><div align="center">&nbsp;</div></td>
	<td ><div align="center">&nbsp;</div></td>
</tr>
<tr><td colspan=7><div id=div_$nodeGroupName style="display:none"></div></td></tr>
EOE;
		return $html;
}

	/**
	 * @param XCATNodeGroup	nodeGroup	The node group for which we want to generate the html.
	 * returns the table that contains all the nodes information of that group
	 */
function getXCATNodeGroupSection($nodeGroup) {
		$config = &Config::getInstance();
		$imagedir = $config->getValue("IMAGEDIR");
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
			$html .= HTMLProducer::getXCATNodeTableRow($node);
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
function getXCATNodeTableRow($node) {

		$config = &Config::getInstance();
		$imagedir = $config->getValue("IMAGEDIR");

		//echo $node->getName();
		$html = "<tr bgcolor=\"#FFFF66\" class=\"indent\">
				<td width=89><input type=\"checkbox\" name=\"node_" .$node->getName(). "\" />" .$node->getName(). "</td>" .
				"<td width=38><div align=center>" . $node->getHwType(). "</div></td>".
				"<td width=22><div align=center>" . $node->getOs(). "</div></td>".
				"<td width=43><div align=center>" . $node->getMode(). "</div></td>";

		$stat = $node->getStatus();
		$img_string = XCATNodeGroupUtil::getImageString($stat);

		$html .= "<td width=43><div align=center>" . $img_string . "</div></td>".
				"<td width=85><div align=center>" . $node->getHwCtrlPt(). "</div></td>".
				"<td width=71><div align=center>" . $node->getComment(). "</div></td></tr>";

EOS;
		return $html;
	}
}
?>

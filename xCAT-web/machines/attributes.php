<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

//echo "<LINK rel=stylesheet href='$TOPDIR/manage/dsh.css' type='text/css'>\n";
//echo "<script type='text/javascript' src='attributes.js'></script>\n";

// Get the noderange
$noderange = @$_REQUEST['noderange'];
//echo "<p>noderange=$noderange.</p>\n";
if (empty($noderange)) { echo "<p>Select one or more groups or nodes.</p>\n"; exit; }

// Get the attributes
$xml = docmd('lsdef',NULL,array($noderange,'-t','node','-l'));
//echo "<p>"; print_r($xml); echo "</p>\n";
$errors = array();
if (getXmlErrors($xml,$errors)) { echo "<p class=Error>lsdef failed: ", implode(' ',$errors), "</p>\n"; exit; }

// Process the lsdef output to get column headers and attributes for each node
$headers = array();
$attrs = array();
//echo "<p>";
foreach ($xml->children() as $response) foreach ($response->children() as $k => $v) {
	$line = (string)$v;		// we assume $k is info
	//echo "$line<br>";
	if (preg_match('/^\s$/', $line)) { continue; }		// ignore blank line

	$matches = array();
	if (preg_match('/^Object name:\s*(.*)$/', $line, $matches)) {
		$nodename = $matches[1];		// all the attributes following will be for this node until we hit another line like this
		$attrs[$nodename] = array();
		//echo "<p>New node: $nodename.</p>\n";
		continue;
		}

	// If we get here, the line is just attr=val
	list($key, $value) = preg_split('/\s*=\s*/', $line, 2);
	//echo "<p>$key = $value.</p>\n";
	$attrs[$nodename][$key] = $value;
	$headers[$key] = 1;
	}
//echo "</p>\n";

// Now display the table with the data we gathered
echo "<FORM NAME=attrForm id=attrForm>\n";
//insertButtons(array('label' => 'Show Attributes', 'id' => 'attrButton', 'onclick' => ''));

// Display links to column descriptions
echo "<p id=helpLinks><a href='" . getDocURL('dbobject','node') . "' target='_blank'>Column Descriptions</a>\n";
echo "<a href='" . getDocURL('dbtable') . "' target='_blank'>Regular Expression Support</a></p>\n";


// Display the column headings
echo "<table id=nodeAttrTable>\n";
echo "<tr class='colHeaders'>\n";
$headers2 = array_keys($headers);
sort($headers2);
echo "<td>Node</td>";
foreach($headers2 as $colHead) { echo "<td>$colHead</td>"; }
echo "</tr>\n"; # close header row

// Save the width of the table for adding a new row when they click that button
//$tableWidth = count($headers);

// Display table contents.  Todo: remember its contents in a session variable.
$ooe = 0;		// alternates the background of the table
//$item = 0;		// the column #
//$line = 0;
//$editable = array();
foreach ($attrs as $node => $attrarray) {
	$cl = "ListLine$ooe";

	// 1st the column for the node name
	echo "<tr class=$cl><td nowrap>$node</td>";

	// Now go thru the column names and display the value if there is one for this node
	foreach($headers2 as $colHead) {
		if (isset($attrarray[$colHead])) $cell = $attrarray[$colHead];
		else $cell = '';
		echo "<td class=editme>$cell</td>";
		//$editable[$line][$item++] = $v;
		}
	echo "</tr>\n";
	//$line++;
	//$item = 0;
	$ooe = 1 - $ooe;
}
echo "</table>\n";


echo "</FORM>\n";
echo "<script type='text/javascript'>attrReady();</script>\n";

//insertNotDoneYet();
?>
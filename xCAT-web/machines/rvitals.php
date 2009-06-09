<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

//echo "<LINK rel=stylesheet href='$TOPDIR/manage/dsh.css' type='text/css'>\n";
//echo "<script type='text/javascript' src='$TOPDIR/manage/dsh.js'></script>\n";

// Get the noderange
$noderange = @$_REQUEST['noderange'];
//echo "<p>noderange=$noderange.</p>\n";
if (empty($noderange)) { echo "<p>Select one or more groups or nodes for rvitals.</p>\n"; exit; }

$xml = docmd('rvitals',$noderange,array('all'));
//echo "<p>"; print_r($xml); echo "</p>\n";
if (getXmlErrors($xml,$errors)) { echo "<p class=Error>rvitals failed: ", implode(' ',$errors), "</p>\n"; exit; }
//echo "<p>"; print_r($xml); echo "</p>\n";

echo "<p>\n";
foreach ($xml->children() as $response) foreach ($response->children() as $o) {
	$nodename = (string)$o->name;
    if(empty($nodename)) {
        continue;
    }
	$data = & $o->data;
	$contents = (string)$data->contents;
	$desc = (string)$data->desc;
	//echo "<p>"; print_r($data); echo "</p>\n";
	echo "$nodename: $desc: $contents<br>\n";
}
echo "</p>\n";


//echo "<FORM NAME=rvitalsForm>\n";


//echo "</FORM>\n";
//echo "<script type='text/javascript'>vitalsReady();</script>\n";

//insertNotDoneYet();
?>

<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

//echo "<LINK rel=stylesheet href='$TOPDIR/manage/dsh.css' type='text/css'>\n";
//echo "<script type='text/javascript' src='$TOPDIR/manage/dsh.js'></script>\n";


//get the noderange
$noderange = @$_REQUEST['noderange'];
if (empty($noderange)) {
   echo "<p>Select one or more groups or nodes for rpower.</p>\n";
    exit;
}
//echo "<p>noderange=$noderange.</p>\n";

$xml = docmd('rpower', $noderange, array('stat'));

if (getXmlErrors($xml,$errors)) {
    echo "<p class=Error>rpower failed:", implode(' ',$errors), "</p>\n";
    exit;
}
//echo "<p>debug<br>";print_r($xml);echo "<br>debug end</p>\n";
echo '<div>';
echo "<p>";
foreach ($xml->children() as $response) foreach ($response->children() as $o) {
    $nodename = (string)$o->name;
    if(empty($nodename)) {
        continue;
    }
    $data = & $o->data;
    $contents = (string)$data->contents;
    $desc = (string)$data->desc;

    echo "$nodename: $contents<br>\n";
}
echo "</p>\n";
echo "</div>\n";

//echo '<div>';
//echo "<p>Rpower Actions</p>";
//echo "</div>\n";

//echo "<FORM NAME=rpowerForm>\n";

//insertButtons(array('label' => 'Show Attributes', 'id' => 'attrButton', 'onclick' => ''));

//echo "</FORM>\n";
//<script type='text/javascript'>dshReady();</script>

//insertNotDoneYet();
?>

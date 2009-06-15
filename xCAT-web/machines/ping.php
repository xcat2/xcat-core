<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

//echo "<LINK rel=stylesheet href='$TOPDIR/manage/dsh.css' type='text/css'>\n";
//echo "<script type='text/javascript' src='$TOPDIR/manage/dsh.js'></script>\n";
echo "<LINK rel=stylesheet href='$TOPDIR/jq/theme/jquery-ui-themeroller.css' type='text/css'>\n";
echo "<script type='text/javascript' src='$TOPDIR/jq/jquery.min.js'></script>\n";
echo "<script type='text/javascript' src='$TOPDIR/jq/jquery-ui-all.min.js'></script>\n";
//use the attributes.css for help
echo "<LINK rel=stylesheet href='$TOPDIR/machines/attributes.css' type='text/css'>\n";

echo <<<CSS1
<style>
body {font-size: 8pt; }
</style>
CSS1;

//Get the noderange
$noderange = @$_REQUEST['noderange'];
if(empty($noderange)) { echo "<p>Select one or more groups or nodes for ping.</p>\n"; exit; }

//pping is one local command, which doesn't use xcat client/server protocol;
$xml = docmd('webrun',"",array("pping $noderange",));#The default pping option is NULL

if(getXmlErrors($xml,$errors)) { echo "<p class=Error>ping failed: ", implode(' ',$errors), "</p>\n"; exit; }

//show the result of "pping"
//TODO
echo "<p>\n"; 
echo <<<TAB1
<table id=nodeAttrTable>
<tr class='colHeaders'>
<th>Node Name</th>
<th>Ping Status</th>
</tr>
TAB1;
foreach ($xml->children() as $response) foreach ($response->children() as $o) {
    $nodename=$o->name;
    if(empty($nodename)) {
        continue;
    }
    $contents = $o->data->contents;
    //echo "$nodename: $contents<br>\n";
    echo "<tr>\n";
    echo "<td>$nodename</td>";
    echo "<td>$contents</td>";
    echo "</tr>\n";

    //echo "$nodename: $contents<br>\n";
}
echo <<<TAB2
</table>
TAB2;
echo "</p>\n";

//echo "<FORM NAME=pingForm>\n";

//insertButtons(array('label' => 'Show Attributes', 'id' => 'attrButton', 'onclick' => ''));

//echo "</FORM>\n";
//<script type='text/javascript'>dshReady();</script>

//insertNotDoneYet();
?>

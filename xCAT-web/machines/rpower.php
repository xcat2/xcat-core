<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

//echo "<LINK rel=stylesheet href='$TOPDIR/manage/dsh.css' type='text/css'>\n";
//echo "<script type='text/javascript' src='$TOPDIR/manage/dsh.js'></script>\n";
echo "<LINK rel=stylesheet href='$TOPDIR/machines/attributes.css' type='text/css'>\n";

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
echo <<<TAB1
<table id=nodeAttrTable>
<tr class='colHeaders'>
<th>Node Name</th>
<th>Rpower Status</th>
</tr>
TAB1;
foreach ($xml->children() as $response) foreach ($response->children() as $o) {
    $nodename = (string)$o->name;
    if(empty($nodename)) {
        continue;
    }
    $data = & $o->data;
    $contents = (string)$data->contents;
    $desc = (string)$data->desc;

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
echo "</div>\n";

//echo "<FORM NAME=rpowerForm>\n";

//insertButtons(array('label' => 'Show Attributes', 'id' => 'attrButton', 'onclick' => ''));

//echo "</FORM>\n";
//<script type='text/javascript'>dshReady();</script>

//insertNotDoneYet();
?>

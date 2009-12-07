<?php


if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$class = $_REQUEST['name'];

if(!isset($class)) {
    exit;
}

$xml = docmd("webrun", "", array("lsrsrcdef-api -r $class | cut -d':' -f1"));
if(getXmlErrors($xml,$errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}

foreach($xml->children() as $response) foreach($response->children() as $data) {
    $attrs = explode("=", $data);
}

$ooe = 0;
$line = 0;
echo<<<EOS0
<b>Available Attributes for $class</b>
<table id="tabTable" class="tabTable" cellspacing="1">
<thead>
    <tr class="colHeaders">
    <td>Class Name</td>
    </tr>
</thead>
<tbody>
EOS0;

foreach($attrs as $attr) {
    $ooe = $ooe%2;
    echo "<tr class='ListLine$ooe' id='row$line'>";
    echo "<td>$attr</td>";
    echo "</tr>";
    $ooe++;
    $line++;
}

echo "</tbody></table>";
?>

<?php
/* 
 * update the condition&response association
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/js/jsonwrapper.php";

$xml = docmd("webrun", "", array("lscondresp"));
if(getXmlErrors($xml,$errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}
//get all the condition&response associations for RMC
foreach ($xml->children() as $response) foreach($response->children() as $data) {
    //get the data from xcatd
    $record = split('"',$data);
    echo "<tr>";
echo <<<TOS6
        <td>$record[1]</td>
        <td>$record[3]</td>
        <td>$record[5]</td>
        <td>$record[7]</td>
TOS6;
    //TODO: insert the button here
    echo "<td>";
    if($record[7] == "Active") {
        echo "<button class='fg-button ui-corner-all ui-state-active' onclick='control_RMCAssoc(\"$record[1]\", \"$record[5]\", \"$record[3]\", \"stop\")'>Disable</button>";
    }else {
        echo "<button class='fg-button ui-corner-all ui-state-active' onclick='control_RMCAssoc(\"$record[1]\", \"$record[5]\", \"$record[3]\", \"start\")'>Enable</button>";
    }
    echo "</td>";
    echo "</tr>";
}
//    echo "</tbody></table>";
?>

<?php

//activate/deactivate the specified condition&response association;
//then, update the content of the table in <div id="association">;
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$cond = '"' . $_REQUEST['c'] . '"';
$node = '"' . $_REQUEST['n'] . '"';
$resp = '"' . $_REQUEST['r'] . '"';
$action = $_REQUEST['a'];

if($action == "start") {
    $xml = docmd("webrun", "", array("startcondresp $cond $resp"));
}else if($action == "stop") {
    $xml = docmd("webrun", "", array("stopcondresp $cond $resp"));
}

if(getXmlErrors($xml,$errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}

//the following code is copied from displayAssociation() in the file: monitor_display.php
echo <<<TOS5
<b>Available Condition/Response Associations</b>
<table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td>Condition</td>
            <td>Response</td>
            <td>Node</td>
            <td>State</td>
            <td>Action</td>
        </tr>
    </thead>
    <tbody>
TOS5;
$xml = docmd("webrun", "", array("lscondresp"));
if(getXmlErrors($xml,$errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}
//get all the condition&response associations for RMC
foreach ($xml->children() as $response) foreach($response->children() as $data) {
    //get the data from xcatd
    $association = explode("=", $data);

    $ooe = 0;
    $line = 0;
    foreach($association as $elem) {
        $ooe = $ooe%2;
        //the format should be
        //"NodeReachability"\t"EmailRootOffShift"\t"hv8plus01.ppd.pok.ibm.com"\t"Active"
        $record = explode("\"", $elem);
        $cond = $record[1];
        $resp = $record[3];
        $node = $record[5];
        $state = $record[7];
        echo "<tr class='ListLine$ooe' id='row$line'>";
        echo "<td>$cond</td>";
        echo "<td>$resp</td>";
        echo "<td>$node</td>";
        echo "<td>$state</td>";
        echo "<td>";
        if($state == "Active") {
            insertButtons(array('label'=>'DeActivate', 'id'=>'deactivate', 'onclick'=>"control_RMCAssoc(\"$cond\", \"$node\", \"$resp\", \"stop\")"));
        }else if($state == "Not active"){
            insertButtons(array('label'=>'Activate', 'id'=>'activate', 'onclick'=>"control_RMCAssoc(\"$cond\", \"$node\", \"$resp\", \"start\")"));
        }
        echo "</td>";
        echo "</tr>";
        $ooe++;
        $line++;
    }
}
echo "</tbody></table>";

?>

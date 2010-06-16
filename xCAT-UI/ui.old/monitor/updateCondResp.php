<?php

// For RMC Event control;
// use "startcondresp" and "stopcondresp" commands to activate/deactivate the specified condition&response;
// the file "updateCondRespTable.php" is used to update the contents in the table of "association".


if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$cond = '"' . $_REQUEST['c'] . '"';
$node = $_REQUEST['n'];
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
else {
    echo "successful";
    exit;
}
?>

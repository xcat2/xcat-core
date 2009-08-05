<?php
/* 
 * Enable/Disable node_stat_monitor feature for the desired plug-in
 * this file is invoked by the file "stat_mon.php"
 * update the table "monitoring",
 */
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];
$action = $_REQUEST['action'];

//TODO:
//right now, we can only go through "webrun" command to run the local command through xcatd
//specially for enable/disable node status monitoring, what I can do is to edit the table "monitoring"
//This method is not suitable!
if($action == 'enable') {
    //chtab name=$name monitoring.nodestatmon='yes'
    $xml=docmd("webrun",'',array("chtab name=$name monitoring.nodestatmon=1"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
}else if($action == 'disable') {
    //chtab name=$name monitoring.nodestatmon=''
    $xml=docmd("webrun",'', array("chtab name=$name monitoring.nodestatmon=no"));
    if(getXmlErrors($xml,$errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
}

echo "successful";
?>

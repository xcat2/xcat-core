<?php
if(!isset($TOPDIR)) { $TOPDIR="..";}
 require_once "$TOPDIR/lib/security.php";
 require_once "$TOPDIR/lib/functions.php";
 require_once "$TOPDIR/lib/display.php";
 require_once "$TOPDIR/lib/monitor_display.php";

displayMapper(array('home'=>'main.php', 'monitor' =>''));

displayTips(array("Click the name of each plugin, you can get the plugin's description.",
        "Select one plugin, choose the options for set up monitoring ",
        "Click the button <b>\"Start\", \"Stop\" or \"Restart\"</b> to setup monitoring plugin"));


//TODO: change the view style;
//Change all the "Actions/Description/Configurations/Views" to Tabs
//And, list all the monitoring plugins under the tree? Not sure now.
displayMonTable();

insertDiv("options");

?>
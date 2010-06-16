<?php
/* 
 * rmc_event_define.php
 * to define the events for RMC
 * the url is: monitor/rmc_event_define.php
 */
if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";


displayMapper(array('home'=>'main.php', 'monitor' =>'monitor/monlist.php', 'RMC Event Setup' => ''));

//displayTips(array(
//        "All the conditions and the responses are here;",
//        "Use \"mkcondition\" and \"mkresponse\" to create new conditions and new responses",
//        "Select the condition, and response to create condition/response association"
//    ));
echo "<div>";
    //TODO:one "text input" widget should be put here, to allow the user to input noderange
displayCondResp();
echo "</div>";
?>

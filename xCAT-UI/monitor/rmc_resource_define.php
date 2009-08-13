<?php
/* 
 * define the performance monitoring using RMC
 */

if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

displayMapper_mon(array('home'=>'main.php', 'monitor'=>'monitor/monlist.php'));

displayTips(array("All the available RMC resources are listed here;",
    "Edit this table to define the RMC performance monitoring;",
    "Select the RMC resource, you can get all the available attributes."));

displayMonsetting();

?>

<div id="monsetting_tips">
    <div id="rmcSrcList"><?php displayRMCRsrc(); ?></div>
    <div id="rmcScrAttr"><?php displayRMCAttr(); ?></div>
</div>


<div><?php displayStatus(); ?></div>
<?php
insertButtons(array('label'=>'Next', 'id'=>'next', 'onclick'=>'loadMainPage("monitor/monlist.php");'));
?>

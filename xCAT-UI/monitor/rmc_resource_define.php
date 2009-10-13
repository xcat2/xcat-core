<?php
/* 
 * define the performance monitoring using RMC
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

//displayMapper(array('home'=>'main.php', 'monitor' =>''));
//
//displayTips(array("All the available RMC resources are listed here;",
//    "Edit this table to define the RMC performance monitoring;",
//    "Select the RMC resource, you can get all the available attributes."));

//displayMonsetting();
echo "<div id='testme'>";
echo "</div>";
echo<<<TOS0
<script type="text/javascript">
$('#testme').load('config.php?t=monsetting');
</script>
TOS0;
echo '<div id="monsetting_tips">';
echo '<div id="rmcSrcList">';
displayRMCRsrc();
echo '</div>';
echo '<div id="rmcScrAttr">';
displayRMCAttr();
echo '</div>';
echo '</div>';


displayStatus();

?>
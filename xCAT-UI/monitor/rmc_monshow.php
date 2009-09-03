<?php
/* 
 * use the xCAT command "monshow" to display the current status for RMC Resources being monitored
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

displayMapper(array('home'=>'main.php', 'monitor' =>''));

displayTips(array("Select the domain: the whole cluser or the compute nodes under \"<b>lpar</b>\",","then select the desired attributes. click the \"OK\" button"));

insertDiv("rmc_tree");

?>

<script type="text/javascript">
    $(init_rmc_ositree());
</script>

<?php

echo "<div id='rmc_monshow'>";
echo "<div id='monshow_opt'></div>";
echo "<div id='monshow_data'></div>";
echo "</div>";

?>
<?php

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$value = $_REQUEST['value'];

echo "<div>";
insertButtons(array('label'=>'Back', 'id'=>'back_btn', 'onclick'=>'rmc_monshow_back_to_opts()'));
echo "</div>";
displayRMCMonshowAttr($value);



?>

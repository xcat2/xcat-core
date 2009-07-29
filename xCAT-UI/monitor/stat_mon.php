<?php
/* 
 * This web page is for "Node status Monitoring" and "Application Status Monitioring",
 * The user can enable/disable "Node/Application Status Monitoring" from this page.
 */
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";


displayStatus();

?>

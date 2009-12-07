<?php
/* 
 * makecondresp.php
 * run the command "mkcondresp" and return the value
 */
if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$cond = '"' . $_REQUEST["cond"] . '"';
$resp = '"' . $_REQUEST["resp"] . '"';
$nr = '"' . $_REQUEST["nr"] . '"';

//Fixit: The parameter $nr can't work right now.
$xml=docmd("webrun", '', array("mkcondresp $cond $resp"));
if(getXmlErrors($xml, $errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}

echo "<p>$resp</p>";

?>

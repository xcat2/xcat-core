<?php

/*
 * setup.php
 * perform the "monstart", "monadd" and "monstop" actions for selected monitoring plugins
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];
$action = $_REQUEST['action'];

//read the "monitoring" table to see whether node status monitoring is enable or not
$xml = docmd("webrun", "", array("gettab name=$name monitoring.nodestatmon"));
if(getXmlErrors($xml, $errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}

foreach($xml->children() as $response) foreach($response->children() as $data)
{
    $nodemonstat = $data;
}
switch($action) {
    case "stop":
        monstop($name, $nmstat);
        break;
    case "restart":
        monrestart($name, $nmstat);
        break;
    case "start":
        monstart($name, $nmstat);
        break;
    default:
        break;
}

function monstop($plugin, $nmstat)
{
    $xml = docmd("monstop", "", array("$plugin","-r"));
    return 0;
}

function monrestart($plugin, $nmstat)
{
    $xml = docmd("monstop", "", array("$plugin", "-r"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
    $xml = docmd("moncfg", "", array("$plugin", "-r"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }

    $xml = docmd("monstart", "", array("$plugin", "-r"));
    return 0;
}

function monstart($plugin, $nmstat)
{
    //TODO:before starting the $plugin,
    //we have to make sure that the plugin is added in the "monitoring" table
    $xml = docmd("monstart", "", array("$plugin", "-r"));
    return 0;
}

?>

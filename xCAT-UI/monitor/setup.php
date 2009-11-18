<?php

/*
 * setup.php
 * to perform the "monstart" and "monstop" actions for the monitoring plugins
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];
$action = $_REQUEST['action'];
$nm = $_REQUEST['nm'];//node status monitoring: yes or no
$noderange = $_REQUEST['nr'];

if($action == "Disable") {
    //FIXIT: it seems rmcmon has sth wrong with monstop
    //The var $noderange can't work
    $xml = docmd("monstop", " ", array("$name", "$noderange" , "-r"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
    $xml = docmd("mondecfg", " ", array("$name", "$noderange"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>", implode(' ', $errors), "</p>";
        exit;
    }
    echo "successful";
}else if($action == "Enable") {
    //at first, check "-n"
    if($nm == "yes") {
        $xml=docmd("monrm", "", array("$name"));
        $xml = docmd("monadd", "", array("$name", "-n"));
    } else if($nm == "no") {
        $xml = docmd("monrm", "", array("$name"));
        $xml = docmd("monadd", "", array("$name"));
    }
    //then, moncfg
    $xml = docmd("moncfg", " ", array("$name", "$noderange"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>", implode(' ', $errors), "</p>";
        exit;
    }
    //special case for rmcmon
    if($name == "rmcmon") {
        $xml = docmd("moncfg", " ", array("$name", "$noderange", "-r"));
        if(getXmlErrors($xml, $errors)) {
            echo "<p class=Error>", implode(' ', $errors), "</p>";
            exit;
        }
    }
    $xml = docmd("monstart", " ", array("$name", "$noderange", "-r"));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>", implode(' ', $errors), "</p>";
        exit;
    }
    echo "successful";
}

//switch($action) {
//    case "stop":
//        monstop($name);
//        break;
//    case "restart":
//        monrestart($name);
//        break;
//    case "start":
//        monstart($name);
//        break;
//    default:
//        break;
//}
//
//function monstop($plugin)
//{
//    $xml = docmd("monstop", "", array("$plugin","-r"));
//    return 0;
//}
//
//function monrestart($plugin)
//{
//    $xml = docmd("monstop", "", array("$plugin", "-r"));
//    if(getXmlErrors($xml, $errors)) {
//        echo "<p class=Error>",implode(' ', $errors), "</p>";
//        exit;
//    }
//    $xml = docmd("moncfg", "", array("$plugin", "-r"));
//    if(getXmlErrors($xml, $errors)) {
//        echo "<p class=Error>",implode(' ', $errors), "</p>";
//        exit;
//    }
//
//    $xml = docmd("monstart", "", array("$plugin", "-r"));
//    return 0;
//}
//
//function monstart($plugin)
//{
//    //Before running "monstart", the command "monls" is used to check
//    $xml = docmd("monls","", NULL);
//    if(getXmlErrors($xml, $errors)) {
//        echo "<p class=Error>",implode(' ', $errors), "</p>";
//        exit;
//    }
//    $has_plugin = false;
//    if(count($xml->children()) != 0) {
//        foreach($xml->children() as $response)  foreach($response->children() as $data) {
//            $arr = preg_split("/\s+/", $data);
//            if($arr[0] == $plugin) {
//                $has_plugin = true;
//            }
//        }
//    }
//    if($has_plugin == false) {
//        //if $has_plugin == false, that means the plugin is not added into the monitoring table
//        $xml = docmd("monadd",'', array("$plugin"));
//        if(getXmlErrors($xml, $errors)) {
//            echo "<p class=Error>",implode(' ', $errors), "</p>";
//            exit;
//        }
//    }
//    //we have to make sure that the plugin is added in the "monitoring" table
//    $xml = docmd("monstart", "", array("$plugin", "-r"));
//    return 0;
//}
//
//?>

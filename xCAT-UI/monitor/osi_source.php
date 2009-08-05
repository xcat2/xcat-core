<?php
/* 
 * osi_source.php
 * to provide the JSON-style data to the function init_ositree();
 */

if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/js/jsonwrapper.php";

//get all the groups
$xml=docmd("lsdef","",array("-t", "group"));
if(getXmlErrors($xml,$errors)) {
    echo "<p class=Error>",implode(' ', $errors), "</p>";
    exit;
}
$groups = array();
$jdata = array();
foreach($xml->children() as $response) foreach($response->children() as $data) {
    //all the groups are stored into $groups
    //TODO
    array_push($groups, $data);
}
//foreach($groups as $group) {
    //$xml = docmd("lsdef","",array("-t", "node", "-w", "nodetype=~osi"))
//}
//print_r($groups);

//echo json_encode($jdata);
echo <<<TOS3
[
{"data":"all","attributes":{
    "id":",all","rel":"group"
    },"state":"closed"
},
{"data":"another","attributes":{
    "id":",another","rel":"group"
    },"state":"open"
}
]
TOS3;
?>

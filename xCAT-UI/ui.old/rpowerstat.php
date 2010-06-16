<?php
/* 
 * rpowerstat.php
 * display the rpower status of all nodes in the whole cluster
 * one graph and one table will be used to display them
 */

if(!isset($TOPDIR)) { $TOPDIR=".";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$type = $_REQUEST['type'];

#if $type == "json", it will return data in json-format
#if $type == "table", it will return the data in one table.

#this hashed table records all the nodes with their status

$xml = docmd("rpower","all",array("stat"));
$nodestat_arr = array();
foreach($xml->children() as $response){
    if($response->errorcode == 0) {
        $key = $response->node->name;
        $nodestat_arr["$key"] = $response->node->data->contents;
    }
}

#print_r($nodestat_arr);
if($type == "table") {
    #output the data into One table
    echo "<table width=100%>";
echo <<<TH00
    <thead>
        <tr><th width=67%>Node Name</th><th width=32%>Status</th></tr>
    </thead>
TH00;
    echo "<tbody>";
    foreach($nodestat_arr as $k => $v) {
        echo "<tr><td>$k</td><td>$v</td></tr>";
    }
    echo "</tbody></table>";
}else if($type == "json") {
    #Currently, we only return the numbers of nodes in different status
    $num_arr = array( array(label => "Operating", data => 0), array( label => "Running", data => 0), array(label => "Not Activated", data => 0), array(label => "Open Firmware", data => 0));
    foreach ($nodestat_arr as $k => $v) {
        switch ($v) {
        case "Operating":
            $num_arr[0][data]++;
            break;
        case "Running":
            $num_arr[1][data]++;
            break;
        case "Not Activated":
            $num_arr[2][data]++;
            break;
        case "Open Firmware":
            $num_arr[3][data]++;
            break;
        }
    }
    #convert the array to JSON-type
    #print_r($num_arr);
    echo json_encode($num_arr);
    return json_encode($num_arr);
}

?>

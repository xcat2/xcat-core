<?php

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];

echo "<p>Available Configurations for  <b>$name</b></p>";

echo '<table id="tabTable" class="tabTable" cellspacing="1">';
echo "<tbody>";

//set up the options for the plugin with the name "$name"
if($name == "rmcmon") {
    //node status monitor, RMC events, RMC resources
    echo "<tr class='ListLine0' id='row0'>";
    echo "<td>Node/Application Status Monitoring Setting</td>";
    echo "<td>";
    insertButtons(array('label'=>'Configure', 'id'=>'rmc_nodestatmon', 'onclick'=>'loadMainPage("monitor/stat_mon.php?name=rmcmon")'));
    echo "</td>";
    echo "</tr>";

    echo "<tr class='ListLine1' id='row1'>";
    echo "<td>RMC Events Monitoring Setting</td>";
    echo "<td>";
    insertButtons(array('label'=>'Configure', 'id'=>'rmc_event', 'onclick'=>'loadMainPage("monitor/rmc_event_define.php")'));
    echo "</td>";
    echo "</tr>";

    echo "<tr class='ListLine0' id='row2'>";
    echo "<td>RMC Resource Monitoring Setting</td>";
    echo "<td>";
    insertButtons(array('label'=>'Configure', 'id'=>'rmc_resource', 'onclick'=>'loadMainPage("monitor/rmc_resource_define.php")'));
    echo "</td>";
    echo "</tr>";

} else {
    //there's only "node status monitoring" is enabled
    echo "<tr class='ListLine0' id='row0'>";
    echo "<td>Node/Application Status Monitoring Setting</td>";
    echo "<td>";
    insertButtons(array('label'=>'Configure', 'id'=>$name."_nodestatmon", 'onclick'=>"loadMainPage(\"monitor/stat_mon.php?name=$name\")"));
    echo "</td>";
    echo "</tr>";
}

echo "</tbody></table>";
?>

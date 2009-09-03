<?php

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];

echo "<div id='monconfig'>";
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

echo "</div>";

echo "<div id='monview'>";
echo "<p>View Options for <b>$name</b></p>";
//there should be many choices for the user to view the clusters' status
echo <<<TOS1
<table id="view_tab" class="tabTable" cellspacing="1">
<thead>
    <tr class='colHeaders'>
        <td>Monitor Items</td>
        <td>Display Formats</td>
    </tr>
</thead>
<tbody>
TOS1;
if($name == "rmcmon") {
    #display two rows, one for RMC event, another for RMC Resource Performance monitoring.
    echo "<tr class='ListLine0' id='row0'>";
    echo "<td>RMC Event Logs</td>";
    echo "<td>";
    insertButtons(array('label'=>'View in Text', 'id'=>'rmc_event_text', 'onclick'=>'loadMainPage("monitor/rmc_lsevent.php")'));
    echo "</td>";
    echo "</tr>";
    echo "<tr class='ListLine1' id='row1'>";
    echo "<td>RMC Resource Logs</td>";
    echo "<td>";
    insertButtons(array('label'=>'View in Text', 'id'=>'rmc_resrc_text', 'onclick'=>'loadMainPage("monitor/rmc_monshow.php")'));
    insertButtons(array('label'=>'View in Graphics', 'id'=>'rmc_resrc_graph', 'onclick'=>''));
    echo "</td>";
    echo "</tr>";
}
else {
    echo "<p>There's no view functions for $name.</p>";
}

echo "</tbody></table></div>";
?>

<?php
/* 
 * show the summary information for the cluster
 */
if(!isset($TOPDIR)) { $TOPDIR=".";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

?>

<div id="clusterprimary">
    <div id="general" class="cluster_subinfo">
        <h5>General Information for the Management Server</h5>
        <?php summary_general(); ?>
    </div>
    <div id="nodestat" class="cluster_subinfo">
        <h5>Power Status of nodes in the cluster</h5>
        <?php showNodeStat(); ?>
    </div>
    <div id="monitor" class="cluster_subinfo">
        <h5>Monitor Information</h5>
        <?php showMonSum(); ?>
    </div>
    <div id="update" class="cluster_subinfo">
        <h5>xCAT Info</h5>
        <?php showxCATInfo(); ?>
    </div>
</div>

<div id="clusternav">
    <h5>Options</h5>
    <ul style="list-style-type:none">
        <li><a href="#" onclick="loadMainPage('control.php')">Power control</a></li>
        <li<a href="#" onclick="loadMainPage('control.php')">Vitals information</a></li>
        <li><a href="#" onclick="loadMainPage('provision.php')" >OS Provision</a></li>
        <li><a href="#" onclick="loadMainPage('config.php')">Configure xCAT Tables</a></li>
        <li><a href="#" onclick="loadMainPage('control.php')" >All Inverntories</a></li>
        <li><a href="#" onclick="loadMainPage('control.php')" >Remote Commands</a></li>
        <li><a href="#" onclick="loadMainPage('monitor/monlist.php')" >Monitor</a></li>
        <li><a href="#" onclick="loadMainPage('monitor.php')" >Syslog</a></li>
        
    </ul>
</div>
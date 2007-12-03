<?php
$TOPDIR = '..';
require_once("$TOPDIR/lib/GroupNodeTable.class.php");

$nodeGroupName = @$_REQUEST["nodeGroupName"];

// Get all the nodes with node information of the group
$nodes = getNodes($nodeGroupName, array('type'));
echo GroupNodeTable::getNodeGroupSection($nodeGroupName, $nodes);

?>

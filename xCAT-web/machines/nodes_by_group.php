<?php

// Returns the nodes of a group expanded in the group/node table

$TOPDIR = '..';
require_once("$TOPDIR/lib/GroupNodeTable.class.php");

$nodeGroupName = @$_REQUEST["nodeGroupName"];

// Get all the nodes (with node information) of the group
$nodes = getNodes($nodeGroupName, array('nodetype.os','nodetype.arch','nodetype.profile','nodehm.power','nodehm.mgt','nodelist.comments'));
//$nodes = getNodes($nodeGroupName, 'nodetype.os');

// Display the rows in the table for these nodes
echo GroupNodeTable::getNodeGroupSection($nodeGroupName, $nodes);

?>

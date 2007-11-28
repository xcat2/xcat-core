<?php
$TOPDIR = '..';
require_once("$TOPDIR/lib/GroupNodeTable.class.php");
require_once("$TOPDIR/lib/XCAT/XCATCommand/XCATCommandRunner.class.php");

$nodeGroupName = @$_REQUEST["nodeGroupName"];

// Get all the nodes with node information of the group
$xcmdr = new XCATCommandRunner();
$nodeGroup = $xcmdr->getXCATNodeByGroupName($nodeGroupName);
echo GroupNodeTable::getNodeGroupSection($nodeGroup);


?>

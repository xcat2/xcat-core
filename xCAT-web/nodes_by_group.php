<?php
require_once("lib/GroupNodeTable.class.php");
require_once("lib/XCAT/XCATCommand/XCATCommandRunner.class.php");

$nodeGroupName = @$_REQUEST["nodeGroupName"];

// Get all the nodes with node information of the group
$xcmdr = new XCATCommandRunner();
$nodeGroup = $xcmdr->getXCATNodeByGroupName($nodeGroupName);
echo GroupNodeTable::getNodeGroupSection($nodeGroup);


?>

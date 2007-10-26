<?php
require_once("globalconfig.php");
require_once("XCAT/HTML/HTMLProducer.class.php");
require_once("XCAT/XCATCommand/XCATCommandRunner.class.php");

$nodeGroupName = @$_REQUEST["nodeGroupName"];

// Get all the nodes with node information of the group
$xcmdr = new XCATCommandRunner();
$nodeGroup = $xcmdr->getXCATNodeByGroupName($nodeGroupName);
echo HTMLProducer::getXCATNodeGroupSection($nodeGroup);


?>

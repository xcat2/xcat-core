<?php
require_once("lib/XCAT/XCATCommand/XCATCommandRunner.class.php");
require_once("lib/XCAT/XCATNode/XCATNodeManager.class.php");
require_once("lib/XCAT/XCATNodeGroup/XCATNodeGroupManager.class.php");

$cmdRunner = new XCATCommandRunner($xCAT_ROOT);
$var = $cmdRunner->getAllXCATNodeGroups();
echo "$var.";
print_r($var);
?>

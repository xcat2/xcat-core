<?php
require_once("globalconfig.php");
require_once("XCAT/XCATCommand/XCATCommandRunner.class.php");
require_once("XCAT/XCATNode/XCATNodeManager.class.php");
require_once("XCAT/XCATNodeGroup/XCATNodeGroupManager.class.php");

$cmdRunner = new XCATCommandRunner($xCAT_ROOT);
$var = $cmdRunner->getAllXCATNodeGroups();
echo "$var.";
print_r($var);
?>

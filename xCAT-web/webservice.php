<?php
/**
 * This file works in conjunction with lib/XCAT/webservice/XCATWebservice.class.php
 */

require_once("globalconfig.php");
require_once("lib/XCAT/webservice/XCATWebservice.class.php");

$methodName = $_REQUEST["method"];

$parameterNames = XCATWebservice::getMethodParameters($methodName);
$parameterHash = array();

foreach($parameterNames as $parameterName) {
	$parameterHash[$parameterName] = $_REQUEST[$parameterName];
}

XCATWebservice::processRequest($methodName, $parameterHash);
?>

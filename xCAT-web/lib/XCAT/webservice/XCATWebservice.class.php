<?php

require_once("XCAT/HTML/HTMLProducer.class.php");

/**
 * This class exposes an API for calling the XCAT PHP classes.
 * It works in conjunction with webservice.php .
 *
 * This class delegates all of its methods to other classes
 * that do all of the actual work.
 */
class XCATWebservice {
	/**
	 * @param String methodName		The name of a static method in the XCATWebservice class.
	 * @param Hash   parameterHash	Parameter names (keys) and values (values) for the method to be called.
	 */
	function processRequest($methodName, $parameterHash) {
		// Only static method can be called when the class name is also provided.
		$classMethod = array("XCATWebservice", $methodName);

		$parameterValues = array_values($parameterHash);

		call_user_func_array($classMethod, $parameterValues);
	}

	/**
	 * @param String methodName		The name of the method whose parameter
	 * 								 names we want.
	 * @return	Returns an array of strings, representing the names of the
	 * 			parameters this method expects. Parameters are provided in
	 * 			the order they are expected.
	 */
	function getMethodParameters($methodName) {
		$parameterNames = array();

		switch($methodName) {
			case "getXCATNodeRows":
				$parameterNames = array("nodeGroupName");
				break;
			// Add case statements for other methods here.
			default:
				$parameterNames = NULL;
				break;
		}

		return $parameterNames;
	}

	function getXCATNodeRows($nodeGroupName) {
		$html = HTMLProducer::getXCATNodeTableRows($nodeGroupName);

		echo $html;
	}
}
?>
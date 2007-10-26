<?php
require_once("XCAT/XCATNode/XCATNodeStatus.class.php");
/**
 * Contains some utilities for XCATNodes.
 */
class XCATNodeUtil {
	function XCATNodeUtil() {

	}

	/**
	 * @param String nodestatStr	The status of the node as output by the nodestat command
	 * @return "good", "bad", or "other"
	 */
	function determineNodeStatus($nodestatStr) {
		$status = NULL;

		if ((strpos($nodestatStr, "ready") != FALSE) ||
			(strpos($nodestatStr, "pbs") != FALSE) ||
			(strpos($nodestatStr, "sshd") != FALSE)) {
			$status = XCATNodeStatus::good();
		} else if(strpos($nodestatStr, "noping") != FALSE) {
			$status = XCATNodeStatus::bad();
		} else {
			$status = XCATNodeStatus::other();
		}

		return $status;
	}
}
?>

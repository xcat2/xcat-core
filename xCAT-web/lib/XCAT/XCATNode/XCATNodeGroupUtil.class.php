<?php
require_once("config.php");

/**
 * Contains some utilities for XCATNodes.
 */
class XCATNodeGroupUtil {

	function XCATNodeGroupUtil() {

	}

	/**
	 * @param String nodestatStr	The status of the node as output by the nodestat command
	 * @return "good", "bad", or "other"
	 */
	function determineNodeStatus($statStr) {
		$status = NULL;

		if ((strpos($statStr, "ready") !== FALSE) ||
			(strpos($statStr, "pbs") !== FALSE) ||
			(strpos($statStr, "noping") === FALSE && strpos($statStr, "ping") !== FALSE ) ||
			(strpos($statStr, "sshd") !== FALSE)) {
			$status = "good";
		} else if(strpos($statStr, "noping") !== FALSE) {
			$status = "bad";
		} else {
			$status = "other";
		}

		return $status;
	}

	/**
	 * Return the image string based on the node/group status
	 */
	function getImageString($status){
			$config = &Config::getInstance();
			$imagedir = $config->getValue("IMAGEDIR");
			$greengif = $imagedir . "/green-ball-m.gif";
			$yellowgif = $imagedir . "/yellow-ball-m.gif";
			$redgif = $imagedir . "/red-ball-m.gif";

			//node/group is good
			if (strstr($status, "good") == TRUE ){
					$stat_content = "<IMG src=\"" . $greengif. "\" alt=\"Node is good\"> ";
			}elseif (strstr($status, "bad") == TRUE){	//node is bad
					$stat_content = "<IMG src=\"" . $redgif. "\" alt=\"Node is bad\"> ";
			}else{	//other status
					$stat_content = "<IMG src=\"" . $yellowgif. "\" alt=\"Other status\"> ";
			}

			return $stat_content;
	}
}
?>

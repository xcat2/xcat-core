<?php
/* Required libraries */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

/**
 * Issue an xCAT command (only for z)
 *
 * @param 	$cmd	The xCAT command
 * 			$tgt	The target node or group
 * 			$args	The xCAT command arguments, separated by semicolons
 * @return The xCAT response.  Replies are in the form of JSON
 */
if (isset($_GET["cmd"])) {
	// HTTP GET requests
	$cmd = $_GET["cmd"];
	$tgt = $_GET["tgt"];
	$args = $_GET["args"];

	// Attachments are put here
	$att = $_GET["att"];

	// Special messages put here
	$msg = $_GET["msg"];

	// If no $tgt is given, set $tgt to NULL
	if (!$tgt) {
		$tgt = NULL;
	}

	// If no $args is given, set $args to NULL
	if (!$args) {
		$args = NULL;
	}

	// If no $msg is given, set $msg to NULL
	if (!$msg) {
		$msg = NULL;
	}

	// If no $att is given, set $att to NULL
	if (!$att) {
		$att = NULL;
	}

	// If $args contains multiple arguments, split it into an array
	if (strpos($args,";")) {
		// Split the arguments into an array
		$arr = array();
		$arr = explode(";", $args);
	} else {
		$arr = array($args);
	}

	$rsp = array();

	// Replace user entry
	if(strncasecmp($cmd, "chvm", 4) == 0 && strncasecmp($arr[0], "--replacevs", 11) == 0) {
		// Directory /var/tmp permissions = 777
		// You can write anything to that directory
		$userEntry = "/var/tmp/$tgt.txt";
		$handle = fopen($userEntry, 'w') or die("Cannot open $userEntry");
		fwrite($handle, $att);
		fclose($handle);

		// CLI command: chvm gpok249 --replacevs /tmp/dirEntry.txt
		// Replace user entry
		array_push($arr, $userEntry);
		$xml = docmd($cmd, $tgt, $arr);
		foreach ($xml->children() as $child) {
			foreach ($child->children() as $data) {
				$data = str_replace(":|:", "\n", $data);
				array_push($rsp, "$data");
			}
		}
	}

	// Create virtual server
	else if(strncasecmp($cmd, "mkvm", 4) == 0) {
		// Directory /var/tmp permissions = 777
		// You can write anything to that directory
		$userEntry = "/var/tmp/$tgt.txt";
		$handle = fopen($userEntry, 'w') or die("Cannot open $userEntry");
		fwrite($handle, $att);
		fclose($handle);

		// CLI command: mkvm gpok3 /tmp/gpok3.txt
		// Create user entry
		array_unshift($arr, $userEntry);
		$xml = docmd($cmd, $tgt, $arr);
		foreach ($xml->children() as $child) {
			foreach ($child->children() as $data) {
				$data = str_replace(":|:", "\n", $data);
				array_push($rsp, "$data");
			}
		}
	}

	// Run shell script
	// This is a typical command used by all platforms.  It is put here because
	// most of the code needed are already here
	else if (strncasecmp($cmd, "xdsh", 4) == 0) {
		// Directory /var/tmp permissions = 777
		// You can write anything to that directory
		$msgArgs = explode(";", $msg);
		$inst = str_replace("out=scriptStatusBar", "", $msgArgs[0]);
		$script = "/var/tmp/script$inst.sh";

		// Write to file
		$handle = fopen($script, 'w') or die("Cannot open $script");
		fwrite($handle, $att);
		fclose($handle);

		// Change it to executable
		chmod($script, 0777);

		// CLI command: xdsh gpok3 -e /var/tmp/gpok3.sh
		// Create user entry
		array_push($arr, $script);
		$xml = docmd($cmd, $tgt, $arr);
		foreach ($xml->children() as $child) {
			foreach ($child->children() as $data) {
				$data = str_replace(":|:", "\n", $data);
				array_push($rsp, "$data");
			}
		}

		// Remove this file
		unlink($script);
	}

	// Reply in the form of JSON
	$rtn = array("rsp" => $rsp, "msg" => $msg);
	echo json_encode($rtn);
}
?>
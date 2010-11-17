<?php
/* Required libraries */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

/**
 * Issue a xCAT command, e.g. rpm -qa xCAT
 * This will handle system commands.
 *
 * @param 	$cmd	The system command
 * @return 	The system response.  Replies are in the form of JSON
 */
if (!isAuthenticated()){
	echo ("<b>Please log in from the main page first!</b>");
	exit;
}

if (isset($_GET["cmd"])) {
	// HTTP GET requests
	$cmd = $_GET["cmd"];
	$ret = "";

	if ("ostype" == $cmd) {
		$ret = strtolower(PHP_OS);
	}
	else {
		$ret = shell_exec($cmd);
	}

	echo json_encode(array("rsp"=>$ret));
}
?>
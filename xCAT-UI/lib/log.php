<?php
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

session_start();

header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT");
header("Cache-Control: no-store, no-cache, must-revalidate");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");

if (isset($_REQUEST["password"])) {
	// Clear data from session
	$_SESSION = array();

	// Zap existing session entirely
	session_regenerate_id(true);
	setpassword($_REQUEST["password"]);

	// Invalid password
	$_SESSION["xcatpassvalid"] = -1;
}

if (isset($_REQUEST["username"])) {
	$_SESSION["username"] = $_REQUEST["username"];

	// Invalid user name
	$_SESSION["xcatpassvalid"]=-1;
}

$jdata = array();
if (isAuthenticated()) {
	$jdata["authenticated"]="yes";
} else {
	$jdata["authenticated"]="no";
}

echo json_encode($jdata);
?>


<?php
/**
 * Main xCAT page
 */
require_once "lib/functions.php";
require_once "lib/ui.php";
require_once "lib/jsonwrapper.php";

/* Load page */
loadPage();

/* Login user */
if (!isAuthenticated()) {
	login();
} else {
	loadContent();
}

/**
 * Test lib/cmd.php
 */
function testCmdPhp() {
	$xml = docmd('lsdef', NULL, array('all'));
	$rsp = array();

	foreach ($xml->children() as $child) {
		foreach ($child->children() as $data) {
			array_push($rsp, "$data");
		}
	}

	$rtn = array("rsp" => $rsp, "msg" => '');
	echo json_encode($rtn);
}
?>
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
	$xml = docmd('rinv', 'ca4dsls08', array('all'));
	$rsp = array();

	foreach ($xml->children() as $child) {
		// Get the 1st level child
		foreach ($child->children() as $level_one) {
			if ($level_one->children()) {
				// Get the 2nd level child
				foreach ($level_one->children() as $level_two) {
					if ($level_two->children()) {
						// Get the 3rd level child
						foreach ($level_two->children() as $level_three) {
							array_push($rsp, "$level_three");
						}
					} else {
						array_push($rsp, "$level_two");
					}
				}
			} else {
				array_push($rsp, "$level_one");
			}
		}
	}
  	
	$rtn = array("rsp" => $rsp, "msg" => '');
	echo json_encode($rtn);
}
?>
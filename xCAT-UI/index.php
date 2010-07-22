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
		foreach ($child->children() as $data) {
			if($data->name) {
				$node = $data->name;
				$cont = $data->data->contents;
				array_push($rsp, "$node: $cont");				
			} else if(strlen("$data") > 2) {
				array_push($rsp, "$data");
			}
		}		
	}
  	
	$rtn = array("rsp" => $rsp, "msg" => '');
	echo json_encode($rtn);
}
?>
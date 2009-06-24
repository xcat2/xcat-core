<?php
	require_once "lib/security.php";
	require_once "lib/functions.php";
	require_once "lib/display.php";
	if(isset($_REQUEST['cmd'])){
		$cmd = $_REQUEST['cmd'];
	}
	displayCtrlPage($cmd);	
	displayNrTree();	

?>

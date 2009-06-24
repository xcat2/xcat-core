<?php
	$u_agent = $_SERVER['HTTP_USER_AGENT'];
	if(preg_match('/MSIE/i', $u_agent)){
		echo "Internet Explorer is not supported at this time.  Please use Firefox\n";
		exit;
	}
	require_once "lib/functions.php";
	require_once "lib/display.php";
	require_once "lib/security.php";
	displayHeader();
	displayBody();
	displayFooter();

	#if(!isAuthenticated()){
	#	insertLogin();
	#}
?>

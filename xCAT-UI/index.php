<?php
	$u_agent = $_SERVER['HTTP_USER_AGENT'];
	if(preg_match('/MSIE 6.0/i', $u_agent)){
		echo "Internet Explorer 6.0 is not supported.  Please use Firefox, Chrome, Safari, IE7 or IE8\n";
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

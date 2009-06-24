<?php
	require_once "lib/security.php";
	require_once "lib/functions.php";
	require_once "lib/display.php";
	$method = "";
	$profile = "";
	$arch = "";
	$os = "";
	# m is the install method: install, netboot
	if(isset($_REQUEST['m'])){
		$method = $_REQUEST['m'];
	}
	# o is the os
	if(isset($_REQUEST['o'])){
		$os = $_REQUEST['o'];
	}
	# a is the architecture
	if(isset($_REQUEST['a'])){
		$arch = $_REQUEST['a'];
	}
	# p is the profile
	if(isset($_REQUEST['p'])){
		$profile = $_REQUEST['p'];
	}

	# put them all together and it spells 'moap'
	# ...which doesn't mean anything.
	displayProvisionPage($method,$os,$arch,$profile);	
	displayNrTree();	

?>

<?php
	require_once "lib/security.php";
	require_once "lib/functions.php";
	require_once "lib/display.php";
	if(isset($_REQUEST['cmd'])){
		$cmd = $_REQUEST['cmd'];
	}
	if(isset($_REQUEST['nr'])){
		$nr = $_REQUEST['nr'];
	}
	if(isset($_REQUEST['args'])){
		$args = $_REQUEST['args'];
	}
	#echo "args: $args<br>";
	$newargs = array();
	$newargs = explode(" ",$args);
	$out = docmd($cmd,$nr,$newargs);
	echo $out;
?>

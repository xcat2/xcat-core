<?php
	header("Cache-Control: no-cache");
	require_once "lib/security.php";
	require_once "lib/functions.php";
	require_once "lib/display.php";
	// gets the last log entry and prints it.
	// start with 0 being the last line
	if(isset($_REQUEST['l'])){
		$ln = $_REQUEST['l'];
	}else{
		$ln = 0;
	}
	$line = getLastLine($ln);
	logTotable($line);
?>

<?php

require_once "functions.php";
require_once "jsonwrapper.php";

$query = '';
$output = '';
$temp = '';
$pythonProcess = '';
if (!isAuthenticated()){
	echo ("Please log in firsr.");
}

$query = 's=' . $_POST['s'] . '&w=' . $_POST['w'] . '&h=' . $_POST['h'];
if (isset($_POST['q'])){
	$query .= '&q=1';
}
else{
	$query .= '&q=0';
}

if (isset($_POST['f'])){
	$pythonProcess = exec('ps -aef | grep -v grep | grep ajaxterm.py');
	if ('' == $pythonProcess){
		exec('nohup ' . dirname(__FILE__) . '/ajaxterm/ajaxterm.py >/dev/null 2>&1 &');
	}

	sleep(1);

	$temp = $query . '&k=' . urlencode($_SESSION["username"] . "\r");
	$output = rconsSynchronise($temp);
	if (0 < substr_count($output, 'error')){
		echo json_encode(array('err'=>$output));
		exit;
	}
	sleep(1);

	$temp = $query . '&k=' . urlencode(getpassword() . "\r");
	$output = rconsSynchronise($temp);
	if (0 < substr_count($output, 'error')){
		echo json_encode(array('err'=>$output));
		exit;
	}
	sleep(1);

	$temp = $query . '&c=1&k=' . urlencode('rcons ' . $_POST['s'] . "\r");
}
else{
	$temp = $query . '&c=1&k=' . urlencode($_POST['k']);
}
 
$output = rconsSynchronise($temp);
if (0 < substr_count($output, 'error')){
	echo (array('err'=>$output));
}
else{
	$xml = simplexml_load_string($output);
	if ('pre' == $xml->getName()){
		$output = $xml->asXML();
		$output = preg_replace('/'. chr(160) . '/', '&nbsp;', $output);

		echo json_encode(array('term'=>$output));
	}
	else{
		echo json_encode(array('nc'=>'nc'));
	}
}

function rconsSynchronise($parameter){
	$flag = false;
	$return = "";
	$out = "";
	$fp = fsockopen("127.0.0.1", 8022, $errno, $errstr, 30);
	if (!$fp) {
		return "<error>$errstr($errno)</error>";
	}

	$out = "GET /u?$parameter HTTP/1.1\r\nHost: 127.0.0.1:8022\r\nConnection: Close\r\n\r\n";

	fwrite($fp, $out);
	while(!feof($fp)){
		$line = fgets($fp,1024);
		if (0 == strlen($line)){
			continue;
		}
		if('<' == substr($line, 0, 1)){
			$flag = true;
			$return .= $line;
			break;
		}
	}
	if ($flag){
		while(!feof($fp)){
			$return .= fgets($fp, 1024);
		}
	}

	return ($return);
}
?>
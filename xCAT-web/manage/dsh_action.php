<?php
/**
 * Action file for running xdsh/psh and output the results to the screen
 */

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";


// HTTP Headers to tell the browser to always update, never cache this page
// so the History combo box always update the new commands added whenever the page is reloaded
header("Expires: Mon, 26 Jul 1997 05:00:00 GMT"); // date in the past
header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT"); // always modified
header("Cache-Control: no-store, no-cache, must-revalidate"); // HTTP/1.1
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache"); // HTTP/1.0

// Store command into history cookie, if it is not already there
$expire_time = gmmktime(0, 0, 0, 1, 1, 2038);
//echo "<p>{$_REQUEST['command']},"; foreach ($_COOKIE['history'] as $h) { echo "$h,"; }; echo "</p>\n";
//echo "<p>" . isset($_COOKIE['history']) . ',' . array_search($_REQUEST['command'], $_COOKIE['history']) . "</p>\n";
if (isset($_COOKIE['history']) && array_search($_REQUEST['command'], $_COOKIE['history'])!==FALSE) {
	// this command is already in the history, so do not need to add it
} else {
	$i = isset($_COOKIE['history']) ? count($_COOKIE['history']) : 0;
	setcookie("history[$i]", $_REQUEST['command'], $expire_time);
}

//print_r($_COOKIE);

	//get the command and the options
	$cmd = @$_REQUEST["command"];
	$copy = @$_REQUEST["copy"];
	$node = @$_REQUEST["node"];
	$group = @$_REQUEST["nodegrps"];
	$psh = @$_REQUEST["psh"];

	$serial = @$_REQUEST["serial"];
	$verify = @$_REQUEST["verify"];
	$collapse = @$_REQUEST["collapse"];
	$fanout = @$_REQUEST["fanout"];
	$userID = @$_REQUEST["userID"];
	$rshell = @$_REQUEST["rshell"];
	$shell_opt = @$_REQUEST["shell_opt"];
	$monitor = @$_REQUEST["monitor"];
	$ret_code = @$_REQUEST["ret_code"];


	if (!empty($group)) $noderange = $group;
	else $noderange = $node;

	if ($serial == "on") $args[] = "-s";	//streaming mode
	if (!empty($fanout)) { $args[] = "-f"; $args[] = $fanout; }
	if (!empty($userID)) { $args[] = "-l"; $args[] = $userID; }
	if ($verify == "on")  $args[] = "-v";
	if ($monitor == "on")  $args[] = "-m";
	if ($copy == "on")  $args[] = "-e";
	if ($ret_code == "on") $args[] = "-z";

	//$exp_cmd = "export DSH_CONTEXT=XCAT XCATROOT=/opt/xcat; ";

/*
	if ($copy == "on"){		//using dcp/prcp

		//extract the script name from the command
		$script = strtok($cmd,' ');

		//copy the command to the remote node
		$source = $script;
		$target = "/tmp";
		if (empty($psh) || $psh!="on"){
			$xml = docmd('xdcp',$noderange,array($source, $target));
			//todo: check if copy succeeded
		}else{
			runcmd("pscp $source $noderange:$target",1,$outp);
		}
		$cmd = "/tmp/$cmd";
	}
*/

	if (empty($psh) || $psh!="on") $command = "xdsh";
	else $command = "psh";

	//if ($collapse == "on")  $command_string .= " | dshbak -c";

	// Run the script
	$args[] = $cmd;
	echo "<p><b>Command:  $command $noderange " . implode(' ',$args) . "</b></p>";
	//echo "<p><b>Command Ouput:</b></br></p>"; //output will be returned from the runcmd function call
	//$rc = runcmd($command_string,1, $outp);	//streaming mode - DOES NOT WORK YET
	$xml = docmd($command, $noderange, $args);
	//echo "<p>count=" . count($xml) . ", children=" . $xml->children() . "</p>";
	//echo "<p>"; print_r($xml); echo "</p>";
	//$output = $xml->xcatresponse->children();
	//echo "<p>"; print_r($output); echo "</p>";
	foreach ($xml->children() as $response) foreach ($response->children() as $line) { echo "$line<br>"; }




		/***************************************************************************************
		 * TEST PART
		 * for now just use system command on the server, not using psh to run cmds on the nodes
		 ***************************************************************************************/

		 //test case 1: mode 1 (or -1)
		/*$rc = runcmd($cmd,1, $outp);
		echo "</br> RC to caller: " . $rc . "</br>";*/
		//passed

		//test case 2: mode 3
		/*$rc = runcmd($cmd,3, $outp, array('NoRedirectStdErr' => TRUE));
		echo "RC to caller: " . $rc . "</br>";
		echo "Ouput file handle: " . $outp . "</br>";
		echo "Results: " . "</br>";
		if ($outp){
			while (!feof($outp)){
				$read = fgets($outp);
				echo $read;
			}
		}*/
		//passed

		//testcase 3: mode 0
		/*$rc = runcmd($cmd,0, $outp, array('NoRedirectStdErr' => TRUE));
		if ($rc == 0)	echo "Results: ";
		foreach ($outp as $key => $val){
			echo $val. ";";
		}*/
		//passed

		//testcase 4: mode 2
		/*$rc = runcmd($cmd,2, $outp, array('NoRedirectStdErr' => TRUE));
		echo "Results: " . $outp;*/
		//passed



		/*
		//history cookie
		if ($rc == 0){ // no error
		if (isset($_COOKIE["history"])){	//append to the old cookie
				//avoid repetitive entries when user hit "Refresh" button
				if (strstr($_COOKIE["history"], ';') == FALSE){  //just have one entry in the history cookie
					if (strcmp($_COOKIE["history"],$cmd_text) <> 0){
						$cmd_history = $_COOKIE["history"] . ";" . $cmd_text;
						setcookie("history",$cmd_history,$expire_time);
					}
				} else {
					$string = $_COOKIE["history"];
					$token = strtok($string, ';');
					$is_repetitive = 0;
					if (strcmp($token,$cmd_text) <> 0)		$is_repetitive = 1;
					while (FALSE !== ($token = strtok(';'))) {
	   					if (strcmp($token,$cmd_text) <> 0)		$is_repetitive = 1;

					}
					if ($is_repetitive == 0){	//the new command is not repetitive
						$cmd_history = $_COOKIE["history"] . ";" . $cmd_text;
						setcookie("history",$cmd_history,$expire_time);
					}
				}
			}
			else{ //first time, write new
				$cmd_history = $cmd_text;
				setcookie("history",$cmd_history,$expire_time);	//cookie lasts 30 days
			}

	}*/

?>
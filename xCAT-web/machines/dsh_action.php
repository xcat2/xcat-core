<?php
/**
 * Action file for running xdsh/psh and output the results to the screen
 */

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";


// HTTP Headers: headers, cookies, ...
header("Expires: Mon, 26 Jul 1997 05:00:00 GMT"); // date in the past
header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT"); // always modified
header("Cache-Control: no-store, no-cache, must-revalidate"); // HTTP/1.1
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache"); // HTTP/1.0

// Store commands into Cookie
//setcookie("history","");
$expire_time = gmmktime(0, 0, 0, 1, 1, 2038);
?>

<FORM>
<?php

//echo "history:" . $_COOKIE["history"];

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


		 if ($group == "")	$nodegrps = "blade7";	// For now, use blade7 as test node

		 if ($psh == "off"){ //using dsh
			$command = "xdsh ";
			$copy_cmd = "xdcp ";
			if ($group == "") $node_group = "-n " . $nodegrps;
			else $node_group = "-N " . $group;

		 }else{
		 	$command = "psh ";
			$copy_cmd = "prcp ";
			if ($group == "") $node_group = $nodegrps;
			else $node_group = $group;
		 }

		if ($serial == "on")	$options = "-s ";	//serial mode/streaming mode
		if ($fanout == "")	$options .= "-f 64 "; else $options .= "-f " . $fanout;
		if ($userID != "")  $options .= "-l " . $userID;
		if ($verify == "on")  $options .= "-v ";
		if ($monitor == "on")  $options .= "-m ";

		//echo "<p>Command: ". $cmd ."</p>";

		//$exp_cmd = "export DSH_CONTEXT=XCAT XCATROOT=/opt/xcat; ";

		if ($copy == "on"){		//using dcp/prcp

			//extract the script name from the command
			$script = strtok($cmd,' ');

			//copy the command to the remote node
			$source = "/opt/xcat/bin/" . $script; //copy from
			$target = "/tmp";	//copy to
			if ($psh == "off"){
				$copy_cmd = $exp_cmd . $copy_cmd . $node_group . " " . $source . " " . $target;
			}else{
				$copy_cmd = $copy_cmd . $source . " " . $node_group . ":" . $target;
			}
			runcmd($copy_cmd,1, $outp);

			if ($psh != "on"){
				$command_string = $exp_cmd . $command. $node_group . " /tmp/" . $cmd;
			}else{
				$command_string = $command . $node_group . " /tmp/" . $cmd;
			}

		}
		else{
			if ($psh != "on"){
				$command_string = $exp_cmd . $command. $node_group . " " . $cmd;
			}else{
				$command_string = $command . $node_group . " " . $cmd;
			}
		}

		if ($collapse == "on")  $command_string .= " | dshbak -c";

		echo "<p><b>Command:  $command_string</b></p>";
		//echo "<p><b>Command Ouput:</b></br></p>"; //output will be returned from the runcmd function call

		//run the script
		$output = array();
		if ($ret_code == "on"){
			$rc = runcmd($command_string, 0, $output);	//mode 0
			if ($rc == 0){
				foreach ($outp as $key => $val){
					echo $val. "</br>";
				}
			}

		}else{
			//$rc = runcmd($command_string,1, $outp);	//streaming mode - DOES NOT WORK YET
			$rc = runcmd($command_string, 0, $output);	//mode 0
			if ($rc == 0){
				foreach ($output as $line){ echo "$line<br>"; }
			}
		}




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
</FORM>




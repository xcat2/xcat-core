<?php
/* Required libraries */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

/**
 * Issue a xCAT command, e.g. rinv gpok123 all
 * This will handle most commands.  If not, you can create your
 * own .php.  Look at zCmd.php for an example.
 *
 * @param 	$cmd	The xCAT command
 * 			$tgt	The target node or group
 * 			$args	The xCAT command arguments, separated by semicolons
 * @return 	The xCAT response.  Replies are in the form of JSON
 */
if (isset($_GET["cmd"])) {
	// HTTP GET requests
	$cmd = $_GET["cmd"];
	$tgt = $_GET["tgt"];
	$args = $_GET["args"];

	// Special messages put here
	// This gets sent back to the AJAX request as is.
	$msg = $_GET["msg"];

	// If no $tgt is given, set $tgt to NULL
	if (!$tgt) {
		$tgt = NULL;
	}
	
	// If no $msg is given, set $msg to NULL
	if (!$msg) {
		$msg = NULL;
	}

	// If no $args is given, set $arr to NULL
	if (!$args) {
		$arr = array();
	} else {
		// If $args contains multiple arguments, split it into an array
		if (strpos($args,";")) {
			// Split the arguments into an array
			$arr = array();
			$arr = explode(";", $args);
		} else {
			$arr = array($args);
		}
	}

	// Submit request and get response
	$xml = docmd($cmd, $tgt, $arr);
	$rsp = array();

	// webrun pping and gangliastatus output needs special handling
	if(strncasecmp($cmd, "webrun", 6) == 0 && (stristr($args, "pping") || stristr($args, "gangliastatus") || stristr($args, "chtab"))) {
		$rsp = extractWebrun($xml);
	}
	// nodels output needs special handling
	else if(strncasecmp($cmd, "nodels", 6) == 0) {
		// Handle the output the same way as webrun
		$rsp = extractNodels($xml);
	}
	// extnoderange output needs special handling
	// This command gets the nodes and groups
	else if(strncasecmp($cmd, "extnoderange", 12) == 0) {
		$rsp = extractExtnoderange($xml);
	}
	// Handle the typical output
	else {
		foreach ($xml->children() as $child) {
			foreach ($child->children() as $data) {
				if($data->name) {
					$node = $data->name;
					
					if($data->data->contents){
						$cont = $data->data->contents;
					}
					else{
						$cont = $data->data;
					}
					
					$cont = str_replace(":|:", "\n", $cont);
					array_push($rsp, "$node: $cont");
				} else if(strlen("$data") > 2) {
					$data = str_replace(":|:", "\n", $data);
					array_push($rsp, "$data");
				}
			}
		}
	}

	// Reply in the form of JSON
	$rtn = array("rsp" => $rsp, "msg" => $msg);
	echo json_encode($rtn);
}

/**
 * Extract the output for a webrun command
 *
 * @param	$xml 	The XML output from docmd()
 * @return 	An array containing the output
 */
function extractWebrun($xml) {
	$rsp = array();
	$i = 0;

	// Extract data returned
	foreach($xml->children() as $nodes){
		foreach($nodes->children() as $node){
			// Get the node name
			$name = $node->name;
			
			// Get the content
			$status = $node->data;
			$status = str_replace(":|:", "\n", $status);

			// Add to return array
			$rsp[$i] = array("$name", "$status");
			$i++;
		}
	}

	return $rsp;
}

/**
 * Extract the output for a nodels command
 *
 * @param	$xml 	The XML output from docmd()
 * @return 	An array containing the output
 */
function extractNodels($xml) {
	$rsp = array();
	$i = 0;

	// Extract data returned
	foreach($xml->children() as $nodes){
		foreach($nodes->children() as $node){
			// Get the node name
			$name = $node->name;
			// Get the content
			$status = $node->data->contents;
			$status = str_replace(":|:", "\n", $status);

			$description = $node->data->desc;
			// Add to return array
			$rsp[$i] = array("$name", "$status", "$description");
			$i++;
		}
	}

	return $rsp;
}

/**
 * Extract the output for a extnoderange command
 *
 * @param 	$xml 	The XML output from docmd()
 * @return 	The nodes and groups
 */
function extractExtnoderange($xml) {
	$rsp = array();

	// Extract data returned
	foreach ($xml->xcatresponse->intersectinggroups as $group) {
		array_push($rsp, "$group");
	}

	return $rsp;
}
?>
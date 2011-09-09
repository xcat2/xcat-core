<?php
/* Required libraries */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

/**
 * Replace the contents of an xCAT table
 *
 * @param 	$tab	The xCAT table
 * @param	$cont	The xCAT table contents
 * @return The xCAT response.  Replies are in the form of JSON
 */
if (isset($_POST["table"])) {
	// HTTP POST requests
	$tab = $_POST["table"];
	$cont = $_POST["cont"];
}

// Create xCAT request
$request = simplexml_load_string('<xcatrequest></xcatrequest>');

// Command is tabrestore
$request->addChild('command', 'tabrestore');

// Setup authentication
$usernode=$request->addChild('becomeuser');
$usernode->addChild('username', $_SESSION["username"]);
$usernode->addChild('password', getpassword());

// Go through each table row
$first = 0;
foreach($cont as $line){
	if($first == 0){
		// The 1st line is the table header
		// It does not need special processing
		// Create string containing all array elements
		$str = implode(",", $line);
		$request->addChild('data', $str);

		$first = 1;
		continue;
	}

	// Go through each column
	foreach($line as &$col){
		// If the column does begins and end with a quote
		// Change quotes to &quot;
		if(!empty($col) && !preg_match('/^".*"$/', $col)) {
			$col = '&quot;' . $col . '&quot;';
		}
	}

	// Sort line
	ksort($line, SORT_NUMERIC);
	$keys = array_keys($line);
	$max = count($line) - 1;
	if($keys[$max] != $max){
		for ($i = 0; $i <= $keys[$max]; $i++) {
			if (!isset($line[$i])) {$line[$i]='';}
		}
		ksort($line, SORT_NUMERIC);
	}

	// Create string containing all array elements
	$str = implode(",", $line);
	// Replace " with &quot;
	$str = str_replace('"', '&quot;', $str);
	// Replace ' with &apos;
	$str = str_replace("'", '&apos;', $str);
	$request->addChild('data', $str);
}

// Run command
$request->addChild('table', $tab);
$xml = submit_request($request, 0, NULL);

// Reply in the form of JSON
$rtn = array("rsp" => $xml);
echo json_encode($rtn);
?>
<?php
/**
 * Contains all common PHP functions needed by most pages
 */

// Retain session variables across page requests
session_start();

// The settings below display error on the screen,
// instead of giving blank pages.
error_reporting(E_ALL);
ini_set('display_errors', true);

/**
 * Description: Run a command using the xCAT client/server protocol
 *
 * @param 	$cmd	The xCAT command
 * 			$nr		Node range or group
 * 			$args	Command arguments
 * @return 	A tree of SimpleXML objects.
 * 			See perl-xCAT/xCAT/Client.pm for the format
 */
function docmd($cmd, $nr, $args){
	// If we are not logged in,
	// do not try to communicate with xcatd
	if (!is_logged()) {
		echo "<p>docmd: Not logged in - cannot run command</p>";
		return simplexml_load_string('<xcat></xcat>', 'SimpleXMLElement', LIBXML_NOCDATA);
	}

	$request = simplexml_load_string('<xcatrequest></xcatrequest>');
	$request->addChild('command', $cmd);
	if(!empty($nr)) { $request->addChild('noderange', $nr); }
	if (!empty($args)) {
		foreach ($args as $a) {
			$request->addChild('arg',$a);
		}
	}

	$usernode=$request->addChild('becomeuser');
	$usernode->addChild('username',$_SESSION["username"]);
	$usernode->addChild('password',getpassword());

	$xml = submit_request($request,0);
	return $xml;
}

/**
 * Used by docmd()
 *
 * @param 	$req	Tree of SimpleXML objects
 * @return 	A tree of SimpleXML objects
 */
function submit_request($req, $skipVerify){
	$xcathost = "localhost";
	$port = "3001";
	$rsp = FALSE;
	$response = '';
	$cleanexit = 0;

	// Open a socket to xcatd
	if($fp = stream_socket_client('ssl://'.$xcathost.':'.$port, $errno, $errstr, 30, STREAM_CLIENT_CONNECT)){

		// The line below makes the call async
		// stream_set_blocking($fp, 0);

		fwrite($fp,$req->asXML());		// Send XML to xcatd
		while(!feof($fp)){				// Read until there is no more
			// Remove newlines and add it to the response
			$response .= preg_replace('/\n/', '', fread($fp, 8192));

			// Look for serverdone response
			$fullpattern = '/<xcatresponse>\s*<serverdone>\s*<\/serverdone>\s*<\/xcatresponse>/';
			$mixedpattern = '/<serverdone>\s*<\/serverdone>.*<\/xcatresponse>/';
			if(preg_match($mixedpattern,$response)) {
				// Transaction is done,
				// Package up XML and return it
				// Remove the serverdone response and put an xcat tag around the rest
				$count = 0;
				$response = preg_replace($fullpattern,'', $response, -1, $count);		// 1st try to remove the long pattern
				if (!$count) { $response = preg_replace($mixedpattern,'', $response) . '</xcatresponse>/'; }		// if its not there, then remove the short pattern
				$response = "<xcat>$response</xcat>";
				$rsp = simplexml_load_string($response,'SimpleXMLElement', LIBXML_NOCDATA);
				$cleanexit = 1;
				break;
			}
		}
		fclose($fp);
	}else{
		echo "<p>xCAT submit request socket error: $errno - $errstr</p>";
	}

	if(! $cleanexit){
		if (preg_match('/^\s*<xcatresponse>.*<\/xcatresponse>\s*$/',$response)) {
			// Probably an error message
			$response = "<xcat>$response</xcat>";
			$rsp = simplexml_load_string($response,'SimpleXMLElement', LIBXML_NOCDATA);
		}
		elseif(!$skipVerify){
			echo "<p>(Error) xCAT response ended prematurely: ", htmlentities($response), "</p>";
			$rsp = FALSE;
		}
	}
	return $rsp;
}

/**
 * Enable password storage to split between cookie and session variable
 *
 * @param 	$data
 * 			$key
 * @return
 */
function xorcrypt($data, $key) {
	$datalen = strlen($data);
	$keylen = strlen($key);
	for ($i=0;$i<$datalen;$i++) {
		$data[$i] = chr(ord($data[$i])^ord($key[$i]));
	}

	return $data;
}

/**
 * Get password
 *
 * @param 	Nothing
 * @return
 */
function getpassword() {
	if (isset($GLOBALS['xcatauthsecret'])) {
		$cryptext = $GLOBALS['xcatauthsecret'];
	} else if (isset($_COOKIE["xcatauthsecret"])) {
		$cryptext = $_COOKIE["xcatauthsecret"];
	} else {
		return false;
	}

	return xorcrypt($_SESSION["secretkey"], base64_decode($cryptext));
}

/**
 * Get the password splitting knowledge between server
 * and client side persistant storage.  Caller should regenerate
 * session ID when contemplating a new user/password, to preclude
 * session fixation, though fixation is limited without the secret.
 *
 * @param 	$password	Password
 * @return 	Nothing
 */
function setpassword($password) {
	$randlen = strlen($password);
	$key = getrandchars($randlen);
	$cryptext = xorcrypt($password,$key);

	// Non-ascii characters, encode it in base64
	$cryptext = base64_encode($cryptext);
	setcookie("xcatauthsecret",$cryptext,0,'/');
	$GLOBALS["xcatauthsecret"] = $cryptext;
	$_SESSION["secretkey"] = $key;
}

/**
 * Get RAND characters
 *
 * @param 	$length		Length of characters
 * @return 	RAND characters
 */
function getrandchars($length) {
	$charset = '0123456789abcdefghijklmnopqrstuvwxyz!@#$%^&*';
	$charsize = strlen($charset);
	srand();
	$chars = '';
	for ($i=0;$i<$length;$i++) {
		$num=rand()%$charsize;
		$chars=$chars.substr($charset,$num,1);
	}

	return $chars;
}

/**
 * Determine if a user/password session exists
 *
 * @param 	Nothing
 * @return 	True 	If user has a session.
 * 			False 	Otherwise
 */
function is_logged() {
	if (isset($_SESSION["username"]) and !is_bool(getpassword())) {
		return true;
	} else {
		return false;
	}
}

/**
 * Determine if a user is currently logged in successfully
 * 
 * @param 	Nothing
 * @return 	True 	If the user is currently logged in successfully
 * 			False 	Otherwise
 */
function isAuthenticated() {
	if (is_logged()) {
		if ($_SESSION["xcatpassvalid"] != 1) {
			$testcred = docmd("authcheck", "", NULL);
			if (isset($testcred->{'xcatresponse'}->{'data'})) {
				$result = "".$testcred->{'xcatresponse'}->{'data'};
				if (is_numeric(strpos("Authenticated",$result))) {
					// Logged in successfully
					$_SESSION["xcatpassvalid"] = 1;
				} else {
					// Not logged in
					$_SESSION["xcatpassvalid"] = 0;
				}
			}
		}
	}

	if (isset($_SESSION["xcatpassvalid"]) and $_SESSION["xcatpassvalid"]==1) {
		return true;
	} else {
		return false;
	}
}

/**
 * Log out of the current user session
 * 
 * @param 	Nothing
 * @return 	Nothing
 */
function logout() {
	// Clear the secret cookie from browser
	if (isset($_COOKIE["xcatauthsecret"])) {
		setcookie("xcatauthsecret",'',time()-86400*7,'/');
	}

	// Expire session cookie
	if (isset($_COOKIE[session_name()])) {
		setcookie(session_name(),"",time()-86400*7,"/");
	}

	// Clear server store of data
	$_SESSION=array();
	session_destroy();
}
?>

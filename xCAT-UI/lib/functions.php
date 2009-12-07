<?php

session_start();  
header("Cache-control: private"); 

function getTabNames() {
        $xml = docmd('tabdump','',NULL);
        $tabs = array();
        foreach ($xml->children() as $response) foreach ($response->children() as $t) { $tabs[] = (string) $t; }
        return $tabs;
}

function docmd($cmd, $nr, $args){
 // If for some reason we are not logged in yet, do not even try to communicate w/xcatd
 if (!is_logged()) {
  echo "<p>Docmd: not logged in yet - can not run command.</p>\n";
  return simplexml_load_string('<xcat></xcat>','SimpleXMLElement', LIBXML_NOCDATA);
    }
 $request = simplexml_load_string('<xcatrequest></xcatrequest>');
 $request->addChild('command',$cmd);
 if(!empty($nr)) { $request->addChild('noderange',$nr); }
 if (!empty($args)) { 
	foreach ($args as $a) { $request->addChild('arg',$a); }
 }
	
    $usernode=$request->addChild('becomeuser');
    $usernode->addChild('username',$_SESSION["username"]);
    $usernode->addChild('password',getpassword());
 #echo $request->asXML();
 $xml = submit_request($request,0);
 return $xml;
}

//-----------------------------------------------------------------------------
// Used by docmd()
// req is a tree of SimpleXML objects
// Returns a tree of SimpleXML objects.  See perl-xCAT/xCAT/Client.pm for the format.
function submit_request($req, $skipVerify){
 #global $cert,$port,$xcathost;
 //$apachehome = '/var/www';  # for sles this should be /var/lib/wwwrun
 //$cert = "$apachehome/.xcat/client-cred.pem";
 $xcathost = "localhost";
 $port = "3001";
 $rsp = FALSE;
 $response = '';
 $cleanexit=0;

 // Open a socket to xcatd
 $context = stream_context_create();  // do not need certificate anymore:  array('ssl'=>array('local_cert' => $cert))
 if($fp = stream_socket_client('ssl://'.$xcathost.':'.$port,$errno,$errstr,30,STREAM_CLIENT_CONNECT,$context)){
  fwrite($fp,$req->asXML());  // send the xml to xcatd
  while(!feof($fp)){    // and then read until there is no more
   $recentdata=fgets($fp);
   $response .= preg_replace('/\n/','', $recentdata);  // remove newlines and add it to the response

   // Look for the serverdone response
   $fullpattern = '/<xcatresponse>\s*<serverdone>\s*<\/serverdone>\s*<\/xcatresponse>/';
   $mixedpattern = '/<serverdone>\s*<\/serverdone>.*<\/xcatresponse>/';
   $recentpattern = '/<\/xcatresponse>/';
   //$shortpattern = '/<serverdone>\s*<\/serverdone>/';
   if(preg_match($recentpattern,$recentdata) && preg_match($mixedpattern,$response)) {  // transaction is done, pkg up the xml and return it
    //echo "<p>", htmlentities($response), "</p>\n";
    // remove the serverdone response and put an xcat tag around the rest
    $count = 0;
    $response = preg_replace($fullpattern,'', $response, -1, $count);  // 1st try to remove the long pattern
    if (!$count) { $response = preg_replace($mixedpattern,'', $response) . '</xcatresponse>/'; }  // if its not there, then remove the short pattern
    $response = "<xcat>$response</xcat>";
    //echo "<p>", htmlentities($response), "</p>\n";
    $rsp = simplexml_load_string($response,'SimpleXMLElement', LIBXML_NOCDATA);
    //echo '<p>'; print_r($rsp); echo "</p>\n";
    $cleanexit = 1;
    break;
   }
  }
  fclose($fp);
 }else{
  echo "<p>xCAT Submit request socket Error: $errno - $errstr</p>\n";
 }
 if(! $cleanexit){
  if (preg_match('/^\s*<xcatresponse>.*<\/xcatresponse>\s*$/',$response)) {
   // It is probably an error msg, that is why we didn't get serverdone
   $response = "<xcat>$response</xcat>";
   $rsp = simplexml_load_string($response,'SimpleXMLElement', LIBXML_NOCDATA);
   }
  elseif(!$skipVerify){
   echo "<p>Error: xCAT response ended prematurely: ", htmlentities($response), "</p>";
   $rsp = FALSE;
  }
 }
 return $rsp;
}

//-----------------------------------------------------------------------------
// Use with submit_request() to get the data fields (output that is not node-oriented)
function getXmlData(& $xml) {
 $data = array();
 foreach ($xml->children() as $response) foreach ($response->children() as $k => $v) {
  if ($k == 'data') { $data[] = (string) $v; }
 }
 return $data;
}

//-----------------------------------------------------------------------------
// Use with submit_request() to get any errors that might have occurred
// Returns the errorcode and adds any error strings to the $error array passed in
function getXmlErrors(& $xml, & $errors) {
 if (!isset($errors)) { $errors = array(); }
 if (!isset($xml) || $xml===FALSE) { $errors[]='rc = 1'; return 1; }
 $errorcode = 0;
 foreach ($xml->children() as $response) foreach ($response->children() as $k => $v) {
  if ($k == 'error') { $errors[] = (string) $v; }
  if ($k == 'errorcode') { $errorcode = (string) $v; }
 }
 if ($errorcode==0 && count($errors)) { $errorcode = -1 * count($errors); }  // the plugin author forgot to set the errorcode
 return $errorcode;
}

function getTabHeaders($xml){
 foreach ($xml->children() as $response) foreach ($response->children() as $line) {
  $line = (string) $line;
  if (ereg("^#", $line)) {
   $line = preg_replace('/^#/','', $line);
   $headers = explode(',', $line); 
   return $headers;
  }
 }
 // If we get here, we never found the header line
 return NULL;
}

//-----------------------------------------------------------------------------
// Parse the columns of 1 line of tabdump output
//Todo: the only thing this doesn't handle is escaped double quotes.
function splitTableFields($line){
        $fields = array();
        $line = ",$line";               // prepend a comma.  this makes the parsing more consistent
        for ($rest=$line; !empty($rest); ) {
                $vals = array();
                // either match everything in the 1st pair of quotes, or up to the next comma
                if (!preg_match('/^,"([^"]*)"(.*)$/', $rest, $vals)) { preg_match('/^,([^,]*)(.*)$/', $rest, $vals); }
                $fields[] = $vals[1];
                $rest = $vals[2];
        }
        return $fields;
}
//----------------------------------------------------------------------------
// SImilar to docmd(), but also takes in data that is the table contents.
function doTabRestore($tab, & $data){
	#$headers = getTabHeaders(docmd('tabdump', '', array($tab)));
	#$headers[0] = "#" . $headers[0];
	#$request->addChild('data', implode(",",$headers));
	$request = simplexml_load_string('<xcatrequest></xcatrequest>');
	$request->addChild('command', 'tabrestore');
	$usernode=$request->addChild('becomeuser');
	$usernode->addChild('username', $_SESSION["username"]);
	$usernode->addChild('password',getpassword());
	$first = 0;
	foreach($data as $line){
		if($first == 0){
			# add this in here because the first one is the # sign
			# and doesn't need special processing!
			$linestr = implode(",",$line);
			$request->addChild('data', $linestr);
			$first = 1;	
			continue;
		}
		foreach($line as &$f){
			if(!empty($f) && !preg_match('/^".*"$/', $f)) {
				$f = '&quot;'.$f.'&quot;';
			}
		}
		ksort($line, SORT_NUMERIC);
		$keys = array_keys($line);
		$maxindex = count($line)-1;
		if($keys[$maxindex] != $maxindex){
			for ($i=0; $i<=$keys[$maxindex]; $i++) { 
				if (!isset($line[$i])) {$line[$i]='';} 
			}
			ksort($line, SORT_NUMERIC);
		}
		$linestr = implode(",",$line);
		$linestr = str_replace('"', '&quot;',$linestr); //todo: should we use the htmlentities function?
		$linestr = str_replace("'", '&apos;',$linestr);
			//echo "<p>addChild:$linestr.</p>\n";
		$request->addChild('data', $linestr);
	}
	$request->addChild('table', $tab);
	$resp = submit_request($request,0);
	return $resp;
}


// Send the keys and values in the primary global arrays
function dumpGlobals() {
 //trace('<b>$_SERVER:</b>');
 //foreach ($_SERVER as $key => $val) { trace("$key=$val."); }
 //trace('<b>$_ENV:</b>');
 //foreach ($_ENV as $key => $val) { trace("$key=$val."); }
 trace('<b>$_GET:</b>');
 foreach ($_GET as $key => $val) { trace("$key=$val."); }
 trace('<b>$_POST:</b>');
 foreach ($_POST as $key => $val) { trace("$key=$val."); }
 trace('<b>$_COOKIE:</b>');
 foreach ($_COOKIE as $key => $val) { trace("$key=$val."); }
 if (isset($_SESSION)) {
  trace('<b>$_SESSION:</b>');
  foreach ($_SESSION as $key => $val) { trace("$key=$val."); }
 }
 trace('<b>$GLOBALS:</b>');
 foreach ($GLOBALS as $key => $val) { trace("$key=$val."); }
}

// Debug output  ------------------------------------
define("TRACE", "1");
function trace($str) { if (TRACE) { echo "<p class=Trace>$str</p>\n"; } }




// some jbj/bp stuff

$xcatcmds = array(
        "rpower" => array("on","off","reset","stat","state","boot","off","cycle"),
        "rvitals" => array("all","temp","wattage","voltage","fanspeed","power","leds","state"),
        "reventlog" => array("all", "clear"),
        "rinv" => array("all", "model", "serial", "vpd", "mprom", "deviceid", "uuid", "guid", "firm", "bios", "diag", "mprom", "sprom", "mparom", "mac", "mtm"),
        "resetboot" => array("net", "hd", "cd", "def", "stat")
);


// take in the 
function attributesOfNodes($ht,$meth) {
	$arr = array();
	if($meth == 'rpower'){
		$arr[] = 'Power Status';
		$arr[] = 'More Actions';
		return($arr);
	}elseif($meth == 'rbeacon'){
		$arr[] = 'Beacon Status';
		$arr[] = 'More Actions';
		return($arr);
	}
        foreach($ht->xcatresponse as $v){
                foreach($v->node as $va){
                        $val = (string) $va->data->desc;
                        if($val == ""){
                                $val = (string) $va->data->contents;
                        }
                        $arr[] = $val;
                }
        }
        $arr = array_unique($arr);
        return($arr);
}

function mkNodeHash ($ht,$cmd){
	$arr = array();
	$name = "";
	$desc = "";
	$cont = "";
	foreach($ht->children() as $response) foreach($response->children() as $node) {
            if($node->name) {
                $name = (string) $node->name;
                $desc = (string) $node->data->desc;
                if($cmd == 'rpower'){
                    $desc = 'Power Status';
                }elseif($cmd == 'rbeacon'){
                    $desc = 'Beacon Status';
                }
                $cont = (string) $node->data->contents;
                if($cont == ''){
                    $cont = (string) $node->error;
                }
                $arr[$name][$desc] = $cont;
            }
//                #print_r($response);
//                $name = (string) $node->name;
//                $desc = (string) $node->data->desc;
//                if($cmd == 'rpower'){
//                        $desc = 'Power Status';
//                }elseif($cmd == 'rbeacon'){
//                        $desc = 'Beacon Status';
//                }
//                $cont = (string) $node->data->contents;
//                if($cont == ''){
//                        $cont = (string) $node->error;
//                }
//                $arr[$name][$desc] = $cont;
	}
	
	// add the more fields so we can click in place.
	if($cmd == 'rpower'){
		foreach($arr as $n => $val){
			$html = "<center><a href='#' onclick='controlCmd(\"rpoweroff\",\"$n\")'>Power Off</a>";
			$html .= " <a href='#' onclick='controlCmd(\"rpoweron\",\"$n\")'>Power On</a>";
			$html .= " <a href='#' onclick='controlCmd(\"rpowerboot\",\"$n\")'>Reboot</a>";
			$html .= " <a href='#' onclick='controlCmd(\"rpowerstat\",\"$n\")'>Status</a></center>";
			$arr[$n]['More Actions'] = $html;
		}		
	}elseif($cmd == 'rbeacon'){
		foreach($arr as $n => $val){
			$html = "<center><a href='#' onclick='controlCmd(\"rbeaconstat\",\"$n\")'>Beacon Light Status</a>";
			$html .= " <a href='#' onclick='controlCmd(\"rbeaconoff\",\"$n\")'>Beacon Off</a>";
			$html .= " <a href='#' onclick='controlCmd(\"rbeaconon\",\"$n\")'>Beacon On</a>";
	
			$arr[$n]['More Actions'] = $html;
		}

	}
	#print_r($arr);
	return($arr);
}

// Get the nth to last line from the syslog
// use the newlines to go through the syslog starting at the end
// 
function getLastLine($line){

				if($line == ''){ $line = 0; };
        $f = "/var/log/messages";
        $fp = fopen($f, 'r');
        if($fp === false){ echo "Couldn't open /var/log/messages.  Hint: chmod 644 /var/log/messages might make it work.\n"; return 0; }
        $pos = -2;
        $t = " ";
	// number of new lines we have seen.
	$count = -1;
	#while($t != "\n"){
	while($count < $line){
   	if(!fseek($fp, $pos, SEEK_END)) {
     	$t = fgetc($fp);
			if($t == "\n"){
				$count++;
			}
     	$pos = $pos - 1;
  	}else {
     	rewind($fp);
    	break;
   	}
  } 
	# got a line
	$t = fgets($fp);
	fclose($fp);
	return ($t);
}

?>

<?php
# cat client-key.pem client-cert.pem ca.pem >>certchain.pem
$version = "0.1";
#$cert = ".xcat/client-cred.pem";
$msg;
$xcathost = "localhost";
$port = "3001";

#if(! file_exists($cert)){
#	echo "$cert does not exist.  Please run xcatwebsetup first";
#}


$xcatcmds = array(
	"rpower" => array("on","off","reset","stat","state","boot","off","cycle"),
	"rvitals" => array("all","temp","wattage","voltage","fanspeed","power","leds","state"),
	"reventlog" => array("all", "clear"),
	"rinv" => array("all", "model", "serial", "vpd", "mprom", "deviceid", "uuid", "guid", "firm", "bios", "diag", "mprom", "sprom", "mparom", "mac", "mtm"),
	"resetboot" => array("net", "hd", "cd", "def", "stat")
);

#function to enable password storage to split between cookie and session variable
function xorcrypt($data,$key) {
    $datalen=strlen($data);
    $keylen=strlen($key);
    for ($i=0;$i<$datalen;$i++) {
        $data[$i]=chr(ord($data[$i])^ord($key[$i]));
    }
    return $data;
}

function getpassword() {
    if (isset($GLOBALS['xcatauthsecret'])) {
        $cryptext=$GLOBALS['xcatauthsecret'];
    } else if (isset($_COOKIE["xcatauthsecret"])) {
        $cryptext = $_COOKIE["xcatauthsecret"];
    } else {
        return false;
    }
    return xorcrypt($_SESSION["secretkey"],base64_decode($cryptext));
}

#remembers the password, splitting knowledge between server and client side
#persistant storage
#Caller should regenerate session id when contemplating a new user/password,
#to preclude session fixation, though fixation is limited without the secret.
function setpassword($password) {
    $randlen=strlen($password);
    $key=getrandchars($randlen);
    $cryptext=xorcrypt($password,$key);
    $cryptext=base64_encode($cryptext); #non-ascii chars, base64 it
#Not bothering with explicit expiration, as time sync would be too hairy
#should go away when browser closes.  Any timeout will be handled server 
#side.  If the session id invalidates and the one-time key discarded,
#the cookie contents are worthless anyway
#nevertheless, when logout happens, cookie should be reaped
    setcookie("xcatauthsecret",$cryptext);
    $GLOBALS["xcatauthsecret"]=$cryptext; #May need it sooner, prefer globals
    $_SESSION["secretkey"]=$key;
}

function getrandchars($length) {
    $charset='0123456789abcdefghijklmnopqrstuvwxyz!@#$%^&*';
    $charsize=strlen($charset);
    srand();
    $chars='';
    for ($i=0;$i<$length;$i++) {
        $num=rand()%$charsize;
        $chars=$chars.substr($charset,$num,1);
    }
    return $chars;
}
        
    
    


#functions for editing tables
function savexCATchanges($file, $tab){
	$request = simplexml_load_string('<xcatrequest></xcatrequest>');
	$request->addChild('command','tabrestore');
	$fh = fopen($file, 'r') or die("can't open $file");
	while(!feof($fh)){
		$line = fgets($fh,4096);
		if(empty($line)){
			continue;	
		}
		$line = str_replace("\"\"", "",$line);
		$line = str_replace("\"", "&quot;",$line);
		$request->addChild('data', $line);
	}
	fclose($fh);
	$request->addChild('table',$tab);
	$resp = submit_request($request, 1);
	# 0 means it didn't work
	return($resp);
}

function splitTableFields($arr){
	$fields = array();
	$fields = explode(',', $arr);
	$rf = array();

	# now we have to do damage control for fields that look like this:
  # "idplx15","idplx,ipmi,compute,all",,,
	$inc = '';
	foreach($fields as $f){
		#if(ereg("\"[a-zA-Z0-9\-\.\:\!\| ]+\"", $f)){
		if(ereg("\"[^\"]+\"", $f)){
			$rf[] = $f;
			continue;
		}
		#if(ereg("^[a-zA-Z0-9\-\. ]+\"", $f)){
		if(ereg("[^\"]+\"", $f)){
			$inc .= ",$f";
			$rf[] = $inc;
			$inc = '';
			continue;
		}
		#if(ereg("\"[a-zA-Z0-9\-\. ]+", $f)){
		if(ereg("\"[^\"]+", $f)){
			$inc .= $f;	
			continue;
		}
		#if(ereg("[a-zA-Z0-9\-\. ]+", $f)){
		if(ereg("[a-zA-Z0-9\-\. ]+", $f)){
			$inc .= ",$f";
			continue;
		}
		$rf[] = "";
	}
	return $rf;
}


function getTabNames() {
	$xml = docmd('tabdump','','');
	$tabs = $xml->xcatresponse->children();
	return $tabs;
}

function getTabHeaders($tab){
	$arr = $tab->xcatresponse->children();
	$line = $arr[0];
	$headers = array();
	$headers = explode(',', $line);
	return $headers;

}


# get the keys of the hash table.
function keysByNodeName($ht) {
	$nh = array();
	foreach($ht->xcatresponse as $v){
		$node = (string) $v->node->name;
		if(!array_key_exists($node, $nh)){
			$nh[$node] = array();
		}
		$desc = (string) $v->node->data->desc;
		$cont = (string) $v->node->data->contents;
		$nh[$node][$desc] = $cont;
	}
	return($nh);	
}

function attributesOfNodes($ht) {
	$arr = array();
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

function parseNodeGroups ($groups){
	# groups is an array that may have duplicate commas in them.
	$arr = array();	
	foreach($groups as $gline){
		$newg = explode(',', $gline);
		foreach($newg as $g){
			if(empty($g)){ continue; }
			if(!array_key_exists($g, $arr)){
				$arr[] = $g;
			}
		}		
	}
	return array_unique($arr);
}

# this is a kluge... should make better data structures.
# but too lazy right now...
function addNodesToGroups($groups, $node){
	$arr = array();
	foreach($groups as $g){
		$arr[$g] = array();
		foreach($node->xcatresponse	as $v){
			foreach($v->node as $n){
				$na = (string) $n->data->contents;	
				$nag = explode(',', $na);
				foreach($nag as $foo){
					if(strcmp($foo,$g) == 0){
						$name = (string) $n->name;
						$arr[$g][] =  $name;
						continue;
					}
				}
			}
		}
	}
	return $arr;
}

function is_logged() {
    if (isset($_SESSION["username"]) and !is_bool(getpassword())) {
        return true;
    } else {
        return false;
    }
}
function logout() {
    #clear the secret cookie from browser.
    #expire cookie a week ago, server time, may not work if client clock way off, but the value will be cleared at least.
    if (isset($_COOKIE["xcatauthsecret"])) {
        setcookie("xcatauthsecret",'',time()-86400*7); #NOTE: though firefox doesn't seem to zap it dynamically from cookie store in
    #the client side dialog, firefox does stop submitting the value.  The sensitivity of the 'stale' cookie even if compromised
    #is negligible, as the session id will be invalidated and the one-time-key needed to decrypt the password is destroyed on the server
    }
    #expire the sesion cookie
    if (isset($_COOKIE[session_name()])) {
        setcookie(session_name(),"",time()-86400*7,"/");
    }
    #clear server store of data
    $_SESSION=array();
    session_destroy();
}
function docmd($cmd, $nr, $arg){
	$request = simplexml_load_string('<xcatrequest></xcatrequest>');
    $usernode=$request->addChild('becomeuser');
    $usernode->addChild('username',$_SESSION["username"]);
    $usernode->addChild('password',getpassword());
	$request->addChild('command',$cmd);
	if(!empty($arg)){
		$request->addChild('arg',$arg);
	}
	#$request->addChild('noderange', 'all');
	if(!empty($nr)){
		$request->addChild('noderange',$nr);
	}
	#echo $request->asXML();	
	$nodes = submit_request($request,0);
	return($nodes);
}

function submit_request($req, $skipVerify){
	global $cert,$port,$xcathost;
	$fp; 
	$rsp = '';
	$pos;
	$response = '';
	$cleanexit=0;
    $moreresponses=1;
	$context = stream_context_create(); #array('ssl'=>array('local_cert' => $cert)));
	if($fp = stream_socket_client('ssl://'.$xcathost.':'.$port,$errno,$errstr,30,
                STREAM_CLIENT_CONNECT,$context)){
		fwrite($fp,$req->asXML());
		while($moreresponses and $fp and !feof($fp)){
            $currline=fgets($fp);
			$response .= $currline;
			$response = preg_replace('/\n/','', $response);
			#$pattern = "<xcatresponse><serverdone></serverdone></xcatresponse>";
			$pattern = "<serverdone>";
			$pos	= strpos($response,$pattern);
			if($pos){
				$cleanexit = 1;
            }
            if ($cleanexit) {
                $pattern = "</xcatresponse>";
                $pos = strpos($currline,$pattern);
            }
            if (is_numeric($pos)) {
				#$response = substr($response, 0, $pos);
                #var_dump($response);
				$response = "<xcat>$response</xcat>";
				#$response = preg_replace('/<xcatresponse>\s+<\/xcat>/','', $response);
				#$response .= "</xcat>";
				#echo htmlentities($response);
				$rsp = simplexml_load_string($response,'SimpleXMLElement', LIBXML_NOCDATA);
                $moreresponses=0;
                break;
			}
		}
		fclose($fp);
	}else{
		echo "xCAT Submit request ERROR: $errno - $errstr<br/>\n";
	}
	if(! $cleanexit){
		if(!$skipVerify){
			echo "Error in xCAT response<br>";
			$rsp = 0;
		}
	}
	return $rsp;
}





?>

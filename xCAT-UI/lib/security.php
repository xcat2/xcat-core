<?php
# all the security stuff...
# you need to include functions for this to work.

function insertLogin() {
// The javascript in xcatauth.js will add the Login button and display the dialog
echo <<<EOS2

<div id=logdialog>
<p id=logdialogTitle>Please enter a username and password</p>
<form method=post id=loginform>
<label for=username>Username </label><input id=username type=text name=username>
<br>
<label for=password>Password </label><input id=password type=password name=password>
</form>
<p><span id=logstatus><br/></span></p>
</div>

EOS2;

}


function is_logged() {
    if (isset($_SESSION["username"]) and !is_bool(getpassword())) {
        return true;
    } else {
        return false;
    }
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
    setcookie("xcatauthsecret",$cryptext,0,'/');
    $GLOBALS["xcatauthsecret"]=$cryptext; #May need it sooner, prefer globals
    $_SESSION["secretkey"]=$key;
}

#function to enable password storage to split between cookie and session variable
function xorcrypt($data,$key) {
    $datalen=strlen($data);
    $keylen=strlen($key);
    for ($i=0;$i<$datalen;$i++) {
        $data[$i]=chr(ord($data[$i])^ord($key[$i]));
    }
    return $data;
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

// Determine if they are currently logged in successfully
function isAuthenticated() {
    if (is_logged()) {
        if ($_SESSION["xcatpassvalid"] != 1) {
            $testcred=docmd("authcheck","",NULL);
            if (isset($testcred->{'xcatresponse'}->{'data'})) {
                $result="".$testcred->{'xcatresponse'}->{'data'};
                if (is_numeric(strpos("Authenticated",$result))) {
                    $_SESSION["xcatpassvalid"]=1; #proven good
                } else {
                    $_SESSION["xcatpassvalid"]=0; #proven bad
                }
            }
        }
    }
    if (isset($_SESSION["xcatpassvalid"]) and $_SESSION["xcatpassvalid"]==1) { return true; }
    else { return false; }
}

function logout() {
    #clear the secret cookie from browser.
    #expire cookie a week ago, server time, may not work if client clock way off, but the value will be cleared at least.
    if (isset($_COOKIE["xcatauthsecret"])) {
        setcookie("xcatauthsecret",'',time()-86400*7,'/'); #NOTE: though firefox doesn't seem to zap it dynamically from cookie store in
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

?>

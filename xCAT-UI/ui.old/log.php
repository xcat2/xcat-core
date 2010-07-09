<?php

header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT");
header("Cache-Control: no-store, no-cache, must-revalidate");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");
require_once "lib/functions.php";
require_once "lib/security.php";
require_once "security/jsonwrapper.php";

    if(isset($_GET["logout"]) or isset($_POST["logout"])){
	logout();
	//insertLogin();
    }
    if (isset($_REQUEST["password"])) {
        $_SESSION=array(); #Clear data from session. prevent session data from migrating in a hijacking?
        session_regenerate_id(true);#Zap existing session entirely..
        setpassword($_REQUEST["password"]);
        $_SESSION["xcatpassvalid"]=-1; #unproven password
    }
    if (isset($_REQUEST["username"])) {
        $_SESSION["username"]=$_REQUEST["username"];
        $_SESSION["xcatpassvalid"]=-1; #unproven password
    }

    $jdata=array();
    if (isAuthenticated()) { $jdata["authenticated"]="yes"; }
    else { $jdata["authenticated"]="no"; }

    echo json_encode($jdata);
?>


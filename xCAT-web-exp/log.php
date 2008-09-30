<?php
    session_start();
    header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT");
    header("Cache-Control: no-store, no-cache, must-revalidate");
    header("Cache-Control: post-check=0, pre-check=0", false);
    header("Pragma: no-cache");
    include "functions.php";
    $successfullogin=0;
    if (isset($_GET["logout"]) or isset($_POST["logout"])) {
        logout();
    }
    if (isset($_POST["password"])) {
        $_SESSION=array(); #Clear data from session. prevent session data from migrating in a hijacking?
        session_regenerate_id(true);#Zap existing session entirely..
        setpassword($_POST["password"]);
        $_SESSION["xcatpassvalid"]=-1; #unproven password
    }
    if (isset($_POST["username"])) {
        $_SESSION["username"]=$_POST["username"];
        $_SESSION["xcatpassvalid"]=-1; #unproven password
    }
    if (is_logged()) {
        if ($_SESSION["xcatpassvalid"] != 1) {
            $testcred=docmd("authcheck","","");
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
    $jdata=array();
    if (isset($_SESSION["xcatpassvalid"]) and $_SESSION["xcatpassvalid"]==1) {
        $jdata["authenticated"]="yes";
    } else {
        $jdata["authenticated"]="no";
    }

    echo json_encode($jdata);
?>


<?php
    session_start();
    include "functions.php";
    $attemptedlogin=0;
    $successfullogin=0;
    if (isset($_GET["logout"])) {
        logout();
    }
    if (isset($_POST["password"])) {
        $_SESSION=array(); #Clear data from session. prevent session data from migrating in a hijacking?
        session_regenerate_id(true);#Zap existing session entirely..
        setpassword($_POST["password"]);
    }
    if (isset($_POST["username"])) {
        $_SESSION["username"]=$_POST["username"];
        $attemptedlogin=1;
    }
    if (is_logged()) {
        $testcred=docmd("authcheck","","");
        if (isset($testcred->{xcatresponse}->{data})) {
            $result="".$testcred->{xcatresponse}->{data};
            if (is_numeric(strpos("Authenticated",$result))) {
                $successfullogin=1;
            }
        }
    }
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>xCAT WebUI</title>
<script type="text/javascript" src="jquery.js"></script>
<script type="text/javascript">
    $(document).ready(function() {
    <? if (isset($_SESSION["username"])) { ?>
        $("#password").focus();
    <? } else { ?>
        $("#username").focus();
    <? } ?>
    $("#username").keydown(function(event) {
        if (event.keyCode==13) {
            $("#password").focus();
        }
    });
    $("#password").keydown(function(event) {
        if (event.keyCode==13) {
            $("#loginform").submit();
        }
    });
    $("#login").click(function(event) {
            $("#loginform").submit();
    });
        
            
        
    });

</script>
</head>
<body>
<?
    if ($successfullogin != 1) {
        if ($attemptedlogin) {
            ?>Login Failed<?
        }
        ?>
        <form id="loginform" method="post" action="login.php">
        Username:<input id="username" type="text" name="username"<?if (isset($_SESSION["username"])) { echo 'value="'.$_SESSION["username"].'"'; } ?>><BR>
        Password:<input id="password" type="password" name="password">
        <button id="login" type="button" name="Login" value="Login">Login</button>
        </form>
        <?
    } else {
        echo "Login Success <a href=\"login.php?logout=1\">Logout</a>";
    }

?>
</body>
</html>

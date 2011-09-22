<?php
/**
 * Main xCAT self-service page
 */
require_once "lib/srv_functions.php";
require_once "lib/ui.php";
require_once "lib/jsonwrapper.php";

/** 
 * Load service page
 */
// Include CSS and Javascripts
echo
'<html>
	<head>
		<title>xCAT Service Portal</title>
		<link rel="shortcut icon" href="images/favicon.ico">
		<link href="css/login.css" rel=stylesheet type="text/css">
		<script type="text/javascript" src="js/jquery/jquery.min.js"></script>
		<script type="text/javascript" src="js/jquery/jquery-ui.min.js"></script>
		<script type="text/javascript" src="js/jquery/jquery.cookie.min.js"></script>
		<script type="text/javascript" src="js/ui.js"></script>
		<script type="text/javascript" src="js/service/service.js"></script>
	</head>';

// Create header menu
echo
'<body>
	<div id="header" class="ui-widget-header">
		<img style="margin: 0px 20px; position: relative; float: left;" src="images/logo.gif" height="100%"/>
		<div style="margin: 10px 20px; position: relative; float: left; color: white; font: bold 14px sans-serif;">xCAT Service Portal</div>';
		
// Create user name and log out section
if (isset($_SESSION['srv_username'])){
	echo 
		"<div>
			<span style='color: white;'>User: {$_SESSION['srv_username']}</span>
			<a href='lib/srv_logout.php'>Log out</a>
		</div>";
}

echo '</div>';

// Create content area
echo '<div class="content" id="content"></div>';

// End of page
echo
	'</body>
</html>';

// Login user
if (!isAuthenticated()) {
	// xcatauth.js will open a dialog box asking for the user name and password
	echo
	'<script src="js/srv_xcatauth.js" type="text/javascript"></script>
	<div id="login">
		<div id="login_form">
			<table>
				<tr><td colspan=5></td></tr>
			    <tr><td align=right><img src="images/logo.png" width="50" height="35"></img></td><td colspan=4 style="font-size: 18px;">eXtreme Cloud Administration Toolkit</td></tr>
			    <tr><td colspan=5></td></tr>
				<tr><td></td><td><label for=username>User name:</label></td><td colspan=2><input type=text name=username></td><td></td></tr>
				<tr><td></td><td><label for=password>Password:</label></td><td colspan=2><input type=password name=password></td><td></td></tr>
				<tr><td></td><td></td><td></td><td align=right><button style="padding: 5px;">Login</button></td><td></td></tr>
				<tr><td></td><td colspan=4><span id=login_status></span></td></tr>
			</table>
		</div>
		<div id="loginfo">Open Source. EPL License.</div>
	</div>';
} else {
	// Initialize page
	echo
	'<script language="JavaScript" type="text/javascript"> 
		$(document).ready(function() {
			initServicePage();
		}); 
	</script>';
}
?>

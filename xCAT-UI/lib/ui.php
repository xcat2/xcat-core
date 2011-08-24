<?php
/**
 * Load page
 *
 * @param 	Nothing
 * @return 	Nothing
 */
function loadPage(){
	// Include CSS and Javascripts
	echo
	'<html>
		<head>
			<title>xCAT Console</title>
			<link rel="shortcut icon" href="images/favicon.ico">
			<link href="css/jquery-ui-1.8.12.start.css" rel=stylesheet type="text/css">
			<link href="css/jquery.dataTables.css" rel=stylesheet type="text/css">
			<link href="css/superfish.css" rel=stylesheet type="text/css">
			<link href="css/jstree.css" rel=stylesheet type="text/css">
			<link href="css/jquery.jqplot.css" rel=stylesheet type="text/css">
			<link href="css/style.css" rel=stylesheet type="text/css">
			<script type="text/javascript" src="js/jquery/jquery-1.5.1.min.js"></script>
			<script type="text/javascript" src="js/jquery/jquery-ui-1.8.12.start.min.js"></script>
			<script type="text/javascript" src="js/ui.js"></script>
		</head>';

	// Header menu
	echo
	'<body>
		<div id="header">
			<ul>
				<li><img src="images/logo.gif" height="100%" style="margin-right: 60px;"/></li>	
				<li><a href="index.php" class="top_link">Nodes</a></li>		
				<li><a href="configure.php" class="top_link">Configure</a></li>
				<li><a href="provision.php" class="top_link">Provision</a></li>
				<li><a href="monitor.php" class="top_link">Monitor</a></li>
				<li><a href="guide.php" class="top_link">Guide</a></li>
			</ul>';
			
	// User name and log out section
	if (isset($_SESSION['username'])){
		echo 
			"<div>
				<span>User: {$_SESSION['username']}</span>
				<a href='lib/logout.php'>Log out</a>
			</div>";
	}

	echo '</div>';
	// Content
	echo '<div class="content" id="content"></div>';

	// End of page
	echo
		'</body>
	</html>';
}

/**
 * Load page content
 *
 * @param 	Nothing
 * @return 	Nothing
 */
function loadContent() {
	// Initialize page
	echo
	'<script language="JavaScript" type="text/javascript"> 
		$(document).ready(function() {
			initPage();
		}); 
	</script>';
}

/**
 * Login user into a new session
 *
 * @param 	Nothing
 * @return 	Nothing
 */
function login() {
	// xcatauth.js will open a dialog box
	// asking for the user name and password
	echo
	'<script src="js/jquery/jquery.cookie.min.js" type="text/javascript"></script>
	<script src="js/xcatauth.js" type="text/javascript"></script>
	<div id="logdialog">
		<div id="loginput" class="ui-corner-all">
			<table>
				<tr><td colspan=5></td></tr>
			    <tr><td align=right><img src="images/logo.png" width="50" height="35"></img></td><td colspan=4><p>eXtreme Cloud Administration Toolkit</p></td></tr>
			    <tr><td colspan=5></td></tr>
				<tr><td></td><td><label for=username>Username:</label></td><td colspan=2><input id=username type=text name=username></td><td></td></tr>
				<tr><td></td><td><label for=password>Password:</label></td><td colspan=2><input id=password type=password name=password></td><td></td></tr>
				<tr><td></td><td></td><td></td><td align=right><button>Login</button></td><td></td></tr>
				<tr><td></td><td colspan=4><span id=logstatus></span></td></tr>
			</table>
		</div>
		<div id="loginfo">Open Source. EPL License</div>
	</div>';
}
?>
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
			<link href="css/jquery.autocomplete.css" rel=stylesheet type="text/css">
			<link href="css/jquery-ui-1.8.custom.css" rel=stylesheet type="text/css">
			<link href="css/jquery.dataTables.css" rel=stylesheet type="text/css">
			<link href="css/superfish.css" rel=stylesheet type="text/css">
			<link href="css/tree.css" rel=stylesheet type="text/css">
			<link href="css/style.css" rel=stylesheet type="text/css">
			<script type="text/javascript" src="js/jquery-1.4.2.min.js"></script>
			<script type="text/javascript" src="js/jquery-ui-1.8.custom.min.js"></script>
			<script type="text/javascript" src="js/jquery.dataTables.min.js"></script>
			<script type="text/javascript" src="js/jquery.form.js"></script>
			<script type="text/javascript" src="js/jquery.jeditable.js"></script>
			<script type="text/javascript" src="js/jquery.autocomplete.js"></script>
			<script type="text/javascript" src="js/jquery.contextmenu.js"></script>
			<script type="text/javascript" src="js/jquery.cookie.js"></script>
			<script type="text/javascript" src="js/jquery-impromptu.3.0.min.js"></script>
			<script type="text/javascript" src="js/superfish.js"></script>
			<script type="text/javascript" src="js/hoverIntent.js"></script>
			<script type="text/javascript" src="js/jquery.tree.js"></script>
			<script type="text/javascript" src="js/ui.js"></script>
			<script type="text/javascript" src="js/configure.js"></script>
			<script type="text/javascript" src="js/monitor.js"></script>
			<script type="text/javascript" src="js/nodes.js"></script>
			<script type="text/javascript" src="js/provision.js"></script>
			<script type="text/javascript" src="js/zUtils.js"></script>
		</head>';

	// Header menu
	echo
	'<body>
		<div id="header">
			<ul>
				<li><img src="images/logo.gif" height="100%"/></li>	
				<li><a href="index.php" class="top_link">Nodes</a></li>		
				<li><a href="configure.php" class="top_link">Configure</a></li>
				<li><a href="provision.php" class="top_link">Provision</a></li>
				<li><a href="monitor.php" class="top_link">Monitor</a></li>
			</ul>
		</div>';

	// Nodes section
	echo '<div class="content" id="nodes_page"></div>';
	// Configure section
	echo '<div class="content" id="configure_page"></div>';
	// Provision section
	echo '<div class="content" id="provision_page"></div>';
	// Monitor section
	echo '<div class="content" id="monitor_page"></div>';

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
	'<script src="js/xcatauth.js" type="text/javascript"></script>
	<div id=logdialog>
		<p>Give the username and password configured in the passwd table</p>
			<form id=loginform>
				<table cellspacing=3>
					<tr><td align=right><label for=username>User name:</label></td><td align=left><input id=username type=text name=username></td></tr>
					<tr><td align=right><label for=password>Password:</label></td><td align=left><input id=password type=password name=password></td></tr>
				</table>
			</form>
		<p><span id=logstatus></span></p>
	</div>';
}
?>
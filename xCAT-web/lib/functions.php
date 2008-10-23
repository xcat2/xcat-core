<?php

// Contains all the common php functions that most pages need.

// Some common/global settings
session_start();     // retain session variables across page requests
if (!isset($TOPDIR)) { $TOPDIR = '..'; }

// The settings below display error on the screen, instead of giving blank pages.
//error_reporting(E_ALL ^ E_NOTICE);
error_reporting(E_ALL);
ini_set('display_errors', true);


//-----------------------------------------------------------------------------
/**
 * Inserts the header part of the HTML and the top part of the page, including the menu.
 * Also includes some common css and js files and the css and js files specified.
 * This function should be called at the beginning of every page.
 * @param String $title The page title that should go in the window title bar.
 * @param array $stylesheets The paths of the styles that are specific to this page.
 * @param array $javascripts The paths of the javascript files that are specific to this page.
 * @param array $currents The keys to the top menu and 2nd menu that represent the current choice for this page.  See insertMenus() for the keys.
 */
function insertHeader($title, $stylesheets, $javascripts, $currents) {
global $TOPDIR;

// Remember the current page so we can open it again the next time they come to the web interface
if ($currents[0] != 'logout') {
	$expire_time = gmmktime(0, 0, 0, 1, 1, 2038);
	foreach ($currents as $key => $value) { setcookie("currentpage[$key]", $value, $expire_time, '/'); }
	}

echo <<<EOS1
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>$title</title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">
<link href="$TOPDIR/lib/style.css" rel=stylesheet type='text/css'>
<link href="$TOPDIR/jq/theme/jquery-ui-theme.css" rel=stylesheet type='text/css'>
<script src="$TOPDIR/jq/jquery.min.js" type="text/javascript"></script>
<script src="$TOPDIR/jq/jquery-ui-all.min.js" type="text/javascript"></script>
<script src="$TOPDIR/lib/functions.js" type="text/javascript"></script>

EOS1;


if ($stylesheets) {
	foreach ($stylesheets as $s) {
		echo "<LINK rel=stylesheet href='$s' type='text/css'>\n";
		}
	}
if ($javascripts) {
	foreach ($javascripts as $j) {
		echo "<script type='text/javascript' src='$j'></script>\n";
		}
	}
echo "</head><body>\n";
echo <<<EOS3
<table id=headingTable border=0 cellspacing=0 cellpadding=0>
<tr valign=top>
    <td><img class=ImgTop src='$TOPDIR/images/topl2.jpg'></td>
    <td class=TopMiddle><img id=xcatImage src='$TOPDIR/images/xCAT_icon-l.gif'></td>
    <td class=TopMiddle width='100%'>

EOS3;
//echo "<div id=top><img id=xcatImage src='$TOPDIR/images/xCAT_icon.gif'><div id=menuDiv>\n";

insertMenus($currents);

echo "</td><td><img class=ImgTop src='$TOPDIR/images/topr2.jpg'></td></tr></table>\n";
//echo "</div></div>\n";     // end the top div

if (!isAuthenticated()) {
	insertLogin();		// display the login dialog and page footer
	exit;		// Do not want to continue with the rest of the page
	// If the login dialog is successful, it will load index.php which will remember what
	// page they were trying to go to.
}
}  // end insertHeader


//-----------------------------------------------------------------------------
// If they are not authenticated yet, display the login dialog
function insertLogin() {
global $TOPDIR;
// The javascript in xcatauth.js will add the Login button and display the dialog
echo <<<EOS2
<script src="$TOPDIR/lib/xcatauth.js" type="text/javascript"></script>
<div id=logdialog>
<p id=logdialogNote>Note: The username and password used must be in the passwd table in the xCAT database.</p>
<form id=loginform><table cellspacing=3>
<tr><td align=right><label for=username>Username:</label></td><td align=left><input id=username type=text name=username></td></tr>
<tr><td align=right><label for=password>Password:</label></td><td align=left><input id=password type=password name=password></td></tr>
</table></form>
<p><span id=logstatus><br/></span></p>
</div>

EOS2;

insertFooter();
}


// This is the data structure that represents the menu for each page.
$MENU = array(
	'machines' => array(
		'label' => 'Machines',
		'default' => 'groups',
		'list' => array(
			'lab' => array('label' => 'Lab Floor', 'url' => "$TOPDIR/machines/lab.php"),
			'frames' => array('label' => 'Racks', 'url' => "$TOPDIR/machines/frames.php"),
			'groups' => array('label' => 'Groups/Nodes', 'url' => "$TOPDIR/machines/groups.php"),
			'discover' => array('label' => 'Discover', 'url' => "$TOPDIR/machines/discover.php"),
			)
		),
	'manage' => array(
		'label' => 'Manage',
		'default' => 'dsh',
		'list' => array(
			'dsh' => array('label' => 'Run Cmds', 'url' => "$TOPDIR/manage/dsh.php"),
			'copyfiles' => array('label' => 'Copy Files', 'url' => "$TOPDIR/manage/copyfiles.php"),
			'cfm' => array('label' => 'Sync Files', 'url' => "$TOPDIR/manage/cfm.php"),
			'hwctrl' => array('label' => 'HW Ctrl', 'url' => "$TOPDIR/manage/hwctrl.php"),
			'diagnodes' => array('label' => 'Diagnose', 'url' => "$TOPDIR/manage/diagnodes.php"),
			)
		),
	'jobs' => array(
		'label' => 'Jobs',
		'default' => 'overview',
		'list' => array(
			'overview' => array('label' => 'Overview', 'url' => "$TOPDIR/jobs/overview.php"),
			//todo:  Vallard fill in rest
			)
		),
	'deploy' => array(
		'label' => 'Deploy',
		'default' => 'osimages',
		'list' => array(
			'osimages' => array('label' => 'OS Images', 'url' => "$TOPDIR/deploy/osimages.php"),
			'prepare' => array('label' => 'Prepare', 'url' => "$TOPDIR/deploy/prepare.php"),
			'deploy' => array('label' => 'Deploy', 'url' => "$TOPDIR/deploy/deploy.php"),
			'monitor' => array('label' => 'Monitor', 'url' => "$TOPDIR/deploy/monitor.php"),
			)
		),
	'config' => array(
		'label' => 'Configure',
		'default' => 'db',
		'list' => array(
			'prefs' => array('label' => 'Preferences', 'url' => "$TOPDIR/config/prefs.php"),
			'db' => array('label' => 'Cluster Settings', 'url' => "$TOPDIR/config/db.php"),
			'mgmtnode' => array('label' => 'Mgmt Node', 'url' => "$TOPDIR/config/mgmtnode.php"),
			'monitor' => array('label' => 'Monitor Setup', 'url' => "$TOPDIR/config/monitor.php"),
			'eventlog' => array('label' => 'Event Log', 'url' => "$TOPDIR/config/eventlog.php"),
			)
		),
	'support' => array(
		'label' => 'Support',
		'default' => 'diagnose',
		'list' => array(
			'diagnose' => array('label' => 'Diagnose', 'url' => "$TOPDIR/support/diagnose.php"),
			'update' => array('label' => 'Update', 'url' => "$TOPDIR/support/updategui.php"),
			'howtos' => array('label' => 'HowTos', 'url' => getDocURL('howto')),
			'manpages' => array('label' => 'Man Pages', 'url' => getDocURL('manpage')),
			'maillist' => array('label' => 'Mail List', 'url' => getDocURL('web','mailinglist')),
			'wiki' => array('label' => 'Wiki', 'url' => getDocURL('web','wiki')),
			'suggest' => array('label' => 'Suggest', 'url' => "$TOPDIR/support/suggest.php"),
			'about' => array('label' => 'About', 'url' => "$TOPDIR/support/about.php"),
			)
		),
	'logout' => array(
		'label' => 'Logout',
		'default' => 'logout',
		'list' => array(
			'logout' => array('label' => 'Logout/Login', 'url' => "$TOPDIR/lib/logout.php"),
			)
		),
	);


//-----------------------------------------------------------------------------
// Insert the menus at the top of the page
//   $currents is an array of the current menu choice tree
function insertMenus($currents) {
	global $TOPDIR;
	global $MENU;
	echo "<table class=MenuTable border=0 cellspacing=0 cellpadding=0>\n";

	insertMenuRow($currents[0], 1, $MENU);

	insertMenuRow($currents[1], 0, $MENU[$currents[0]]['list']);

	echo "</table>\n";
}


//-----------------------------------------------------------------------------
// Insert one set of choices under a main choice.
function insertMenuRow($current, $isTop, $items) {
	global $TOPDIR;
	//$img = "$TOPDIR/images/h3bg_new.gif";
	//$menuRowClass = $isTop ? '' : 'class=MenuRowBottom';
	$menuItemClass = $isTop ? '' : 'class=MenuItemBottom';
	//$currentClass = $isTop ? 'class=CurrentMenuItemTop' : '';

	//echo "<TABLE class=MenuTable id=mainNav cellpadding=0 cellspacing=0 border=0><tr>\n";
	//echo "<div class=$menuRowClass><ul id=mainNav>\n";
	//echo "<tr><td $menuRowClass><ul id=mainNav>\n";
	//echo "<tr><td><ul id=mainNav>\n";
	echo "<tr><td>\n";

	foreach ($items as $key => $value) {
		$label = $value['label'];
		if ($isTop) {
			$url = $value['list'][$value['default']]['url'];      // get to the list of submenu choices, choose the default one, and get its url
		} else {
			$url = $value['url'];
		}
		if ($key == $current){
			//echo "<TD><a id=$key href='$link[1]'>$link[0]</a></TD>\n";
			//echo "<li><p $currentClass>$label</p></li>";
			//echo "<li><p>$label</p></li>";
			//echo "<p class=CurrentMenuItem>$label</p>";
			echo "<span class=CurrentMenuItem>$label</span>";
		} else {
			//echo "<TD><a class=NavItem id=$key href='$link[1]'>$link[0]</a></TD>\n";
			//echo "<li><a $menuItemClass id=$key href='$url'>$label</a></li>";
			echo "<a $menuItemClass id=$key href='$url'>$label</a>";
		}
	}

	//echo "</TR></TABLE>\n";
	//echo "</ul></div>\n";
	//echo "\n</ul></td></tr>\n";
	echo "\n</td></tr>\n";
}


//-----------------------------------------------------------------------------
// Inserts the html for each pages footer
function insertFooter() {
echo '<div class=PageFooter><p id=disclaimer>This interface is still under construction and not yet ready for production use.</p></div></BODY></HTML>';
}


//-----------------------------------------------------------------------------
// Run a cmd via the xcat client/server protocol
// args is an array of arguments to the cmd
// Returns a tree of SimpleXML objects.  See perl-xCAT/xCAT/Client.pm for the format.
function docmd($cmd, $nr, $args){
	// If for some reason we are not logged in yet, do not even try to communicate w/xcatd
	if (!is_logged()) {
		echo "<p>Docmd: not logged in yet - can not run command.</p>\n";
		return simplexml_load_string('<xcat></xcat>','SimpleXMLElement', LIBXML_NOCDATA);
    }
	$request = simplexml_load_string('<xcatrequest></xcatrequest>');
	$request->addChild('command',$cmd);
	if(!empty($nr)) { $request->addChild('noderange',$nr); }
	if (!empty($args)) { foreach ($args as $a) { $request->addChild('arg',$a); } }
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
	//$apachehome = '/var/www';		# for sles this should be /var/lib/wwwrun
	//$cert = "$apachehome/.xcat/client-cred.pem";
	$xcathost = "localhost";
	$port = "3001";
	$rsp = 0;
	$response = '';
	$cleanexit=0;

	// Open a socket to xcatd
	$context = stream_context_create();		// do not need certificate anymore:  array('ssl'=>array('local_cert' => $cert))
	if($fp = stream_socket_client('ssl://'.$xcathost.':'.$port,$errno,$errstr,30,STREAM_CLIENT_CONNECT,$context)){
		fwrite($fp,$req->asXML());		// send the xml to xcatd
		while(!feof($fp)){				// and then read until there is no more
			$response .= preg_replace('/\n/','', fgets($fp));		// remove newlines and add it to the response

			// Look for the serverdone response
			$fullpattern = '/<xcatresponse>\s*<serverdone>\s*<\/serverdone>\s*<\/xcatresponse>/';
			$mixedpattern = '/<serverdone>\s*<\/serverdone>.*<\/xcatresponse>/';
			//$shortpattern = '/<serverdone>\s*<\/serverdone>/';
			if(preg_match($mixedpattern,$response)) {		// transaction is done, pkg up the xml and return it
				//echo "<p>", htmlentities($response), "</p>\n";
				// remove the serverdone response and put an xcat tag around the rest
				$count = 0;
				$response = preg_replace($fullpattern,'', $response, -1, $count);		// 1st try to remove the long pattern
				if (!$count) { $response = preg_replace($mixedpattern,'', $response) . '</xcatresponse>/'; }		// if its not there, then remove the short pattern
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
		if(!$skipVerify){
			echo "<p>Error: xCAT response ended prematurely: ", htmlentities($response), "</p>";
			$rsp = 0;
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
	$errorcode = 0;
	foreach ($xml->children() as $response) foreach ($response->children() as $k => $v) {
		if ($k == 'error') { $errors[] = (string) $v; }
		if ($k == 'errorcode') { $errorcode = (string) $v; }
	}
	return $errorcode;
}



/** ----------------------------------------------------------------------------------------------
 Function to run the commands on the remote nodes. Four arguments:
 		1. The command
		2. Mode:
			  0: If successful, return output to a reference variable in the caller function, with the newlines removed.
			  	 Otherwise, print the error msg to the screen
		  	  2: Like mode 0, if successful, return output to a reference variable in the caller function, with the newlines removed.
		  	     But error msgs are output to reference variable in the caller function
			  1: Long running cmd, intermediate results/errors are ouput as the command is executed
			  3: Long running cmd. Results/errors are output to a file and return a file handle to the caller function
		3. Reference variable to hold the output returned to caller function
		4. Reference to an options hash, e.g. { NoVerbose => 1, NoRedirectStderr => 1 }
	Return status: 0 - successful, error - 1
------------------------------------------------------------------------------------------------*/
function runcmd ($cmd, $mode, &$output, $options=NULL){

	//Set error output to the same source as standard output (on Linux)
	if (strstr($cmd,'2>&1') == FALSE && !$options["NoRedirectStdErr"]) { $cmd .= ' 2>&1'; }

	if (!isSupported('ClientServer')) { $cmd = "/usr/bin/sudo $cmd"; }
	//todo: add support for xcat 2

	$ret_stat = "";
	//$arr_output = NULL;
	if ($mode == 3) {    // long running cmd - pipe output to file handle
		$handle = popen($cmd, "r");
		if($handle) {
			$output = $handle;	//return file handle to caller
			return 0;	//successful
		} else {
			msg('E', "Piping command ($cmd) into a file handle failed.");
			return 1;
		}
	}elseif ($mode == 0 || $mode == 2 ){
		exec($cmd, $output, $ret_stat);
		if ($ret_stat == 0){
			//$output = $arr_output;
		} else {
			//output the error msg to the screen
			if ($mode == 0)	foreach ($output as $line) { msg('E', $line); }
			//output error msg to the caller function
			//elseif ($mode == 2) $output = $arr_output[0];   // error is already in the output
		}
	} elseif ($mode == 1){
		echo "<code>\n";
		system($cmd, $ret_stat);
		echo "</code>\n";
	}
	return $ret_stat;
}


//-----------------------------------------------------------------------------
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


//-----------------------------------------------------------------------------
function getXcatRoot() { return isset($_ENV['XCATROOT']) ? $_ENV['XCATROOT'] : '/opt/xcat'; }


//-----------------------------------------------------------------------------
# Returns true if the given rpm file is already installed at this version or higher.
function isInstalled($rpmfile) {
	$aixrpmopt = isAIX() ? '--ignoreos' : '';
	$lang = isWindows() ? '' : 'LANG=C';    //todo: add this back in
	$out = array();
	$rc = runcmd("rpm -U $aixrpmopt --test $rpmfile", 2, $out);
	# The rc is not reliable in this case because it will be 1 if it is already installed
	# of if there is some other problem like a dependency is not satisfied.  So we parse the
	# output instead.
	if (preg_grep('/package .* already installed/', $out)) { return 1; }
	else { return 0; }
  }


$isSupportedHash = array();

//-----------------------------------------------------------------------------
# Returns true if the specified feature is supported.  This is normally determined by some fast
# method like checking for the existence of a file.  The answer is also cached for next time.
function isSupported($feature) {
  if (isset($isSupportedHash[$feature])) { return $isSupportedHash[$feature]; }

  # These are supported in xCAT 2.0 and above
  if ($feature == 'ClientServer'
	  || $feature == 'DB')
	{ $isSupportedHash[$feature] = file_exists(getXcatRoot() . '/bin/xcatclient'); }

  # These are supported in xCAT x.x and above
  //elseif ($feature == 'DshExecute')
  //	{ $isSupportedHash[$feature] = -e '/opt/csm/bin/csmsetuphwmaint'; }

  else { return false; }

  return $isSupportedHash[$feature];
}



// Debug output  ------------------------------------
define("TRACE", "1");
function trace($str) { if (TRACE) { echo "<p class=Trace>$str</p>\n"; } }


//-----------------------------------------------------------------------------
// Take in a hostname or ip address and return the fully qualified primary hostname.  If resolution fails,
// it just returns what it was given.
function resolveHost($host) {
	if (isIPAddr($host)) {       // IP address
		$hostname = gethostbyaddr($host);
		return $hostname;
	}
	else {    //todo: implement resolution of hostname to full primary hostname with just one call
		$ip = gethostbyname($host);
		if (!isIPAddr($ip)) { return $host; }
		$hostname = gethostbyaddr($ip);
		return $hostname;
	}
}

//-----------------------------------------------------------------------------
function isIPAddr ($host) { return preg_match('/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/', $host); }


//-----------------------------------------------------------------------------
// Returns the URL for the requested documentation.  This provides 1 level of indirection in case
// the location of some of the documentation changes.
// book is the name (minus the dollar sign) of one of the arrays below.
// section is the book/website/table name, or in the case of manpage:  cmd.section#
function getDocURL($book, $section = NULL) {
	global $TOPDIR;
	$web = array (
		   'docs' => "http://xcat.svn.sourceforge.net/svnroot/xcat/xcat-core/trunk/xCAT-client/share/doc",
		   'mailinglist' => "http://xcat.org/mailman/listinfo/xcat-user",
		   'updates' => "http://xcat.sourceforge.net/yum",
		   'opensrc' => "http://xcat.sourceforge.net/yum",
		   'wiki' => "http://xcat.wiki.sourceforge.net",
		   );
	$manpage = array(
				0 => "$TOPDIR/../xcat-doc",
				1 => "$TOPDIR/../xcat-doc/man1/xcat.1.html",
				);
	$dbtable = array(
				0 => "$TOPDIR/../xcat-doc/man5",
				1 => "$TOPDIR/../xcat-doc/man5/xcatdb.5.html",
				);
	$howto = array(
				0 => "$TOPDIR/../xcat-doc",
				1 => "$TOPDIR/../xcat-doc/index.html",
				'linuxCookbook' => "$TOPDIR/../xcat-doc/xCAT2.pdf",
				'idataplexCookbook' => "$TOPDIR/../xcat-doc/xCAT-iDpx.pdf",
				'aixCookbook' => "$TOPDIR/../xcat-doc/xCAT2onAIX.pdf",
				);
	/*
	$rsctadmin = array (		//todo:  update this
				0 => "http://publib.boulder.ibm.com/infocenter/clresctr/vxrx/topic/com.ibm.cluster.rsct.doc/rsct_aix5l53",
				1 => "$rsctadmin[0]/bl5adm1002.html",
				 'sqlExpressions' => "$rsctadmin[0]/bl5adm1042.html#ussexp",
				 'conditions' => "$rsctadmin[0]/bl5adm1041.html#cmrcond",
				 'responses' => "$rsctadmin[0]/bl5adm1041.html#cmrresp",
				 'resourceClasses' => "$rsctadmin[0]/bl5adm1039.html#lavrc",
				);
	$rsctref = array (		//todo:  update this
				0 => "http://publib.boulder.ibm.com/infocenter/clresctr/vxrx/topic/com.ibm.cluster.rsct.doc/rsct_linux151",
				1 => "$rsctref[0]/bl5trl1002.html",
			   'errm' => "$rsctref[0]/bl5trl1067.html#errmcmd",
			   'errmScripts' => "$rsctref[0]/bl5trl1081.html#errmscr",
			   'sensor' => "$rsctref[0]/bl5trl1088.html#srmcmd",
			   'auditlog' => "$rsctref[0]/bl5trl1095.html#audcmd",
			   'lscondresp' => "$rsctref[0]/bl5trl1071.html#lscondresp",
			   'startcondresp' => "$rsctref[0]/bl5trl1079.html#startcondresp",
			  );
	*/

	if ($book) {
		//$url = &$$book;
		if ($book=='web') $url = & $web;
		elseif ($book=='manpage') $url = & $manpage;
		elseif ($book=='dbtable') $url = & $dbtable;
		elseif ($book=='howto') $url = & $howto;
		else return NULL;

		if (!$section) { return $url[1]; }     // link to whole book if no section specified
		if ($book=='manpage') {
			$m = explode('.',$section);		// 1st part is cmd name, 2nd part is man section
			return "$url[0]/man$m[1]/$m[0].$m[1].html";
		}
		elseif ($book=='dbtable') { return "$url[0]/$section.5.html"; }
		else return $url[$section];
	}
	else {          // produce html for a page that contains all the links above, for testing purposes
		return '';        //todo:
	}
}


$HWTypeInfo = array (
		  'x335' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8676' ),
		  'x336' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8837' ),
		  'x306' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8836' ),
		  'x306m' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8849,8491' ),
		  'x3550' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7978' ),
		  'e325' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8835' ),
		  'e326' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8848' ),
		  'e326m' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7969' ),
		  'e327' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'' ),
		  'x3250' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'4190,4194' ),
		  'x3350' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'4192,4193,hmc' ),  # just guessed about hmc
		  'x3450' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7948' ),
		  'x3455' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7940,ipmi,xseries,default' ),
		  'x3550' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7978' ),

		  'x340' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8656' ),
		  'x342' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8669' ),
		  'x345' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8670' ),
		  'x346' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8840' ),
		  'x3650' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'7979' ),
		  'x3655' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'7943' ),

		  'x360' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8686' ),
		  'x365' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8862' ),
		  'x366' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8863' ),
		  'x445' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
		  'x450' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
		  'x455' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
		  'x460' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),

		  'x3755' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>4, 'aliases'=>'7163,8877' ),
		  'x3850' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>4, 'aliases'=>'7141,7233' ),
		  'x3950' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>4, 'aliases'=>'' ),  # 7141,7233

		  'hs20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8678,8843,7981,blade' ),   # removed 8832 because it is older and it made this entry to wide in the drop down boxes
		  'hs12' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8014,8028' ),
		  'hs21' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'7995,8853' ),
		  'js20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8842' ),
		  'js12' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'799860X' ),
		  'js21' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8844,7998J21' ),
		  'js22' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'799861X' ),
		  'qs21' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'0792' ),
		  'qs22' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'0793' ),
		  'ls20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8850' ),
		  'ls21' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'7971' ),
		  'ls22' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'7901' ),
		  'hs40' => array ( 'image'=>'blade2.gif', 'rackimage'=>'blade2-front', 'u'=>7, 'aliases'=>'8839' ),
		  'ls41' => array ( 'image'=>'blade2.gif', 'rackimage'=>'blade2-front', 'u'=>7, 'aliases'=>'7972' ),
		  'ls42' => array ( 'image'=>'blade2.gif', 'rackimage'=>'blade2-front', 'u'=>7, 'aliases'=>'7902' ),

		# POWER 4 servers
		  'p610' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>5, 'aliases'=>'7028' ),
		  'p615' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>4, 'aliases'=>'7029' ),
		  'p630' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>4, 'aliases'=>'' ),  # 7026
		  'p640' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>5, 'aliases'=>'7026' ),
		  'p650' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>8, 'aliases'=>'7038' ),
		  'p655' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'7039' ),
		  'p670' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'' ),  # 7040
		  'p690' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'7040' ),

		# OpenPOWER servers
		  'p710' => array ( 'image'=>'342.gif', 'rackimage'=>'x335-front', 'u'=>2, 'aliases'=>'9123' ),
		  'p720' => array ( 'image'=>'520.gif', 'rackimage'=>'x345-front', 'u'=>4, 'aliases'=>'9124' ),

		# POWER 5 servers
		  'p5-505' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'' ),  # 9115
		  'p5-505Q' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'9115' ),

		  'p5-510' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9110' ),
		  'p5-510Q' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'' ),  # 9110
		  'p5-575' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9118' ),

		  'p5-520' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9111' ),
		  'p5-520Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9131' ),
		  'p5-550' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9113' ),
		  'p5-550Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9133' ),
		  'p5-560' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9116' ),
		  'p5-560Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'' ),  # 9116
		  'p5-570' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'' ),  # 9117

		  'p5-590' => array ( 'image'=>'590.gif', 'rackimage'=>'p5-590-front', 'u'=>42, 'aliases'=>'' ),  # 9119
		  'p5-595' => array ( 'image'=>'590.gif', 'rackimage'=>'p5-590-front', 'u'=>42, 'aliases'=>'' ),  # 9119

		# POWER 6 servers
		  '520' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'8203' ),
		  '550' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'8204' ),
		  '570' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9117' ),
		  '575' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9125' ),
		  '595' => array ( 'image'=>'590.gif', 'rackimage'=>'p5-590-front', 'u'=>42, 'aliases'=>'9119' ),
		 );


//-----------------------------------------------------------------------------
// This returns important display info about each type of hardware, so we can easily add new hw types.
function getHWTypeInfo($hwtype, $attr=NULL) {
global $HWTypeInfo;

// Get the aliases defined as keys, if we have not done that yet
if (!array_key_exists('9119',$HWTypeInfo)) {
	$keys = array_keys($HWTypeInfo);		// make a copy of the keys, because we will be adding some in the loop below
	foreach ($keys as $key) {
		$value = $HWTypeInfo[$key];
		if (array_key_exists('aliases',$value) && !empty($value['aliases'])) {
			$aliases = explode(',', $value['aliases']);
			foreach ($aliases as $a) {
				if (array_key_exists($a,$HWTypeInfo)) { msg('W', "Internal warning: Duplicate alias in HWTypeInfo array: $a"); }
				else { $HWTypeInfo[$a] = $value; }
			}
		}
	}
}

// Now return the info requested
$k = strtolower($hwtype);
if (!array_key_exists($k,$HWTypeInfo)) { return NULL; }
$info = $HWTypeInfo[$k];
if (isset($attr)) { return $info[$attr]; }
else { return $info; }
}


//-----------------------------------------------------------------------------
// Returns the image that should be displayed for this type of hw.  Gets this from getHWTypeInfo()
function getHWTypeImage($hwtype, $powermethod) {
	# 1st try to match the hw type
	$info = getHWTypeInfo($hwtype, 'image');
	if (!empty($info)) { return $info; }

	# No matches yet.  Use the power method to get a generic type.
	if (isset($powermethod)) {
		$info = getHWTypeInfo($powermethod, 'image');
		if (!empty($info)) { return $info; }
	}

	# As a last resort, return the most common node image
	return getHWTypeInfo('default', 'image');
}


//-----------------------------------------------------------------------------
// Map the many possible values of nodelist.status into one of four:  good, bad, warning, unknown
//todo: update this list from Lings new status work
function mapStatus($statStr) {
	$status = NULL;
	if ($statStr == "alive" || $statStr == "ready" || $statStr == "pbs" || $statStr == "sshd") { $status = "good"; }
	else if ($statStr == "noping" || $statStr=='unreachable') { $status = "bad"; }
	else if ($statStr == "ping") { $status = "warning"; }
	else { $status = "unknown"; }
	return $status;
}


//-----------------------------------------------------------------------------
// For 2 status strings from nodestat or nodelist.status, return the "lowest" (worst).
// Use this function when trying to aggregate multiple status values into one.
//todo: update this list from Lings new status work
function minStatus($s1, $s2) {
	$statnum = array( 'unknown' => 0,
					'unreachable' => 1,
					'noping' => 1,
					'ping' => 2,
					'snmp' => 3,
					'sshd' => 4,
					'pbs' => 5,
					'ready' => 6,
					'alive' => 6,
					);

	// if either value is empty, just return the other one
	if (!isset($s1)) { return $s2; }
	if (!isset($s2)) { return $s1; }

	// if either value does not map into the hash, then return unknown
	if (!isset($statnum[$s1]) || !isset($statnum[$s2])) { return 'unknown'; }

	if ($statnum[$s1] < $statnum[$s2]) { return $s1; }
	else { return $s2; }
}


//-----------------------------------------------------------------------------
// Return the image that represents the status string passed in
function getStatusImage($status) {
	global $TOPDIR;
	if ($status == 'good') { return "$TOPDIR/images/green-ball-m.gif"; }
	elseif ($status == 'warning') { return "$TOPDIR/images/yellow-ball-m.gif"; }
	elseif ($status == 'bad') { return "$TOPDIR/images/red-ball-m.gif"; }
	else { return "$TOPDIR/images/blue-ball-m.gif"; }
}


//-----------------------------------------------------------------------------
// Returns the specified user preference value, or the default.  (The preferences are stored in cookies.)
// If no key is specified, it will return the list of preference names.
function getPref($key) {
	$prefDefaults = array(
		'nodesPerPage' => 40,
		'displayCmds' => 0,
		);
	if (!isset($key)) { return array_keys($prefDefaults); }
	if (isset($_COOKIE[$key])) { return $_COOKIE[$key]; }
	return $prefDefaults[$key];         // return default if not in the cookie
}


//-----------------------------------------------------------------------------
// Returns a list of some or all of the nodes in the cluster and some of their attributes.
// Pass in a node range (or NULL to get all nodes) and an array of attribute names (or NULL for none).
// Returns an array where each key is the node name and each value is an array of attr/value pairs.
// attrs is an array of attributes that should be returned.
function getNodes($noderange, $attrs) {
	//my ($hostname, $type, $osname, $distro, $version, $mode, $status, $conport, $hcp, $nodeid, $pmethod, $location, $comment) = split(/:\|:/, $na);
	//$nodes[] = array('hostname'=>"node$i.cluster.com", 'type'=>'x3655', 'osname'=>'Linux', 'distro'=>'RedHat', 'version'=>'4.5', 'status'=>1, 'conport'=>$i, 'hcp'=>"node$i-bmc.cluster.com", 'nodeid'=>'', 'pmethod'=>'bmc', 'location'=>"frame=1 u=$", 'comment'=>'');
	$nodes = array();
	if (empty($noderange)) { $nodrange = '/.*'; }
	//$xml = docmd('nodels',$noderange,implode(' ',$attrs));
	$xml = docmd('nodels',$noderange,$attrs);
	foreach ($xml->children() as $response) foreach ($response->children() as $o) {
		$nodename = (string)$o->name;
		$data = & $o->data;
		$attrval = (string)$data->contents;
		if (empty($attrval)) { continue; }
		$attrname = (string)$data->desc;
		//echo "<p> $attrname = $attrval </p>\n";
		//echo "<p>"; print_r($nodename); echo "</p>\n";
		//echo "<p>"; print_r($o); echo "</p>\n";
		//$nodes[$nodename] = array('osversion' => $attr);
		if (!array_key_exists($nodename,$nodes)) { $nodes[$nodename] = array(); }
		$attributes = & $nodes[$nodename];
		$attributes[$attrname] = $attrval;
	}
	return $nodes;
}

//function awalk($value, $key) { echo "<p>$key=$value.</p>\n"; }
//function awalk2($a) { foreach ($a as $key => $value) { if (is_array($value)) {$v='<array>';} else {$v=$value;} echo "<p>$key=$v.</p>\n"; } }


//-----------------------------------------------------------------------------
// Returns the node groups defined in the cluster.
function getGroups() {
	$groups = array();
	$xml = docmd('tabdump','',array('nodelist'));
	//$output = $xml->xcatresponse->children();
	#$output = $xml->children();	// technically, we should iterate over the xcatresponses, because there can be more than one
	//foreach ($output as $line) {
	foreach ($xml->children() as $response) foreach ($response->children() as $line) {
		$line = (string) $line;
		//echo "<p>line=$line</p>";
		if (ereg("^#", $line)) { continue; }	// skip the header
		$vals = splitTableFields($line);
		if (empty($vals[0]) || empty($vals[1])) continue;	// node or groups missing
		$grplist = preg_split('/,/', $vals[1]);
		foreach ($grplist as $g) { $groups[$g] = 1; }
	}
	$grplist = array_keys($groups);
	sort($grplist);
	return $grplist;
}

//-----------------------------------------------------------------------------
// Returns true if we are running on AIX
function isAIX() { }     //todo: implement

//-----------------------------------------------------------------------------
// Returns true if we are running on Linux
function isLinux() { }     //todo: implement

//-----------------------------------------------------------------------------
// Returns true if we are running on Windows
function isWindows() { return array_key_exists('WINDIR', $_SERVER); }


//-----------------------------------------------------------------------------
// Create file folder-like tabs.  Tablist is an array of label/url pairs.
function insertTabs ($tablist, $currentTabIndex) {
	echo "<TABLE cellpadding=4 cellspacing=0 width='100%' summary=Tabs><TBODY><TR>";
	foreach ($tablist as $key => $tab) {
		if ($key != 0) { echo "<TD width=2></TD>"; }
		if ($currentTabIndex == $key) {
			echo "<TD align=center background='$TOPDIR/images/tab-current.gif'><b>$tab[0]</b></TD>";
			}
		else {
			echo "<TD align=center background='$TOPDIR/images/tab.gif'><A href='$tab[1]'>$tab[0]</A></TD>";
			}
	}
    echo "</TR><TR><TD colspan=7 height=7 bgcolor='#CBCBCB'></TD></TR></TBODY></TABLE>\n";
}


//-----------------------------------------------------------------------------
// Create the Action buttons in a table.  Each argument passed in is a button, which is an array of attribute strings.
// If your onclick attribute contains javascript code that uses quotes, use double quotes instead of single quotes.
function insertButtons () {
	$num = func_num_args();
	/* if ($num > 1) */ echo "<TABLE cellpadding=0 cellspacing=2><TR>";
	foreach (func_get_args() as $button) {
		//echo "<td><INPUT type=submit class=but $button ></td>";
		$otherattrs = @$button['otherattrs'];
		$id = @$button['id'];
		if (!empty($id)) { $id = "id=$id"; }
		/* if ($num > 1) */ echo "<td>";
		echo "<a class=button $id href='' onclick='{$button['onclick']};return false' $otherattrs><span>{$button['label']}</span></a>";
		/* if ($num > 1) */ echo "</td>";
		}
	/* if ($num > 1) */ echo "</TR></TABLE>\n";
}


//-----------------------------------------------------------------------------
// Display messages in the html.  If severity is W or E, it will attempt to use the Error class
// from the style sheet.
function msg($severity, $msg)
  {
	//if ($severity=~/V/ && !$::GUI_VERBOSE) { return; }
	if (preg_match('/O/', $severity)) { echo "$msg\n";  return; }
	$styleclass = 'Info';
	if (preg_match('/[WE]/', $severity)) { $styleclass = 'Error'; }
	echo "<P class=$styleclass>$msg</P>\n";
  }


//-----------------------------------------------------------------------------
function insertNotDoneYet() { echo "<p class=NotDone>This page is not done yet.</p>\n"; }

//-----------------------------------------------------------------------------
// Parse the columns of 1 line of tabdump output
//Todo: the only thing this doesn't handle is escaped double quotes.
function splitTableFields($line){
	$fields = array();
	$line = ",$line";		// prepend a comma.  this makes the parsing more consistent
	for ($rest=$line; !empty($rest); ) {
		$vals = array();
		// either match everything in the 1st pair of quotes, or up to the next comma
		if (!preg_match('/^,"([^"]*)"(.*)$/', $rest, $vals)) { preg_match('/^,([^,]*)(.*)$/', $rest, $vals); }
		$fields[] = $vals[1];
		$rest = $vals[2];
	}
	return $fields;
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

// Determine if they at least have a user/pw that they have entered (that may or may not be valid)
function is_logged() {
    if (isset($_SESSION["username"]) and !is_bool(getpassword())) {
        return true;
    } else {
        return false;
    }
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

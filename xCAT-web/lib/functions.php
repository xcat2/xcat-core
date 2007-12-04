<?php

// Contains all the common php functions that most pages need.

// Some common/global settings
session_start();     // retain session variables across page requests

// The settings below display error on the screen, instead of giving blank pages.
error_reporting(E_ALL ^ E_NOTICE);
ini_set('display_errors', true);

// Todo: get rid of these globals
$XCATROOT = '/opt/xcat/bin';
$CURRDIR = '/opt/xcat/web';


/*-----------------------------------------------------------------------------------------------
	Function to insert the header part of the HTML and the top part of the page
------------------------------------------------------------------------------------------------*/
function insertHeader($title, $stylesheets, $javascripts, $currents) {
global $TOPDIR;
if (!$TOPDIR) 	$TOPDIR = '..';

echo <<<EOS
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>$title</title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">
<link href="$TOPDIR/lib/style.css" rel="stylesheet">
<script src="$TOPDIR/lib/functions.js" type="text/javascript"></script>

EOS;

// These are only needed for popup windows, so only need it for specific pages like groups & dsh
//echo "<script src='$TOPDIR/lib/GroupNodeTableUpdater.js' type='text/javascript'> </script>\n";

//echo "<script src='$TOPDIR/js/prototype.js' type='text/javascript'></script>\n";
//echo "<script src='$TOPDIR/js/scriptaculous.js?load=effects' type='text/javascript'></script>\n";
//echo "<script src='$TOPDIR/js/effects.js' type='text/javascript'> </script>\n";

//echo "<script src='$TOPDIR/js/window.js' type='text/javascript'></script>\n";
//echo "<link href='$TOPDIR/themes/default.css' rel='stylesheet' type='text/css'/>\n";

//echo "<link href='$TOPDIR/css/xcattop.css' rel='stylesheet'>\n";
//echo "<link href='$TOPDIR/css/xcat.css' rel='stylesheet'>\n";


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
echo <<<EOS
<table id=headingTable border=0 cellspacing=0 cellpadding=0>
<tr valign=top>
    <td><img src='$TOPDIR/images/topl.jpg'></td>
    <td class=TopMiddle><img id=xcatImage src='$TOPDIR/images/xCAT_icon-l.gif' height=40px></td>
    <td class=TopMiddle width='100%'>

EOS;
//echo "<div id=top><img id=xcatImage src='$TOPDIR/images/xCAT_icon.gif'><div id=menuDiv>\n";

insertMenus($currents);

echo "</td><td><img src='$TOPDIR/images/topr.jpg'></td></tr></table>\n";
//echo "</div></div>\n";     // end the top div
}  // end insertHeader


// Insert the menus at the top of the page
//   $currents is an array of the current menu choice tree
function insertMenus($currents) {
	global $TOPDIR;
	echo "<table border=0 cellspacing=0 cellpadding=0>\n";

	insertMenuRow($currents[0], 1, array(
		'machines' => array('Machines', "$TOPDIR/machines/groups.php"),
		'jobs' => array('Jobs', "$TOPDIR/jobs/overview.php"),
		'deploy' => array('Deploy', "$TOPDIR/deploy/osimages.php"),
		'config' => array('Configuration', "$TOPDIR/config/site.php"),
		'support' => array('Support', "$TOPDIR/support/diagnose.php")
	));
	if ($currents[0] == 'machines') {
		insertMenuRow($currents[1], 0, array(
			'lab' => array('Lab Floor', "$TOPDIR/machines/lab.php"),
			'frames' => array('Frames', "$TOPDIR/machines/frames.php"),
			'groups' => array('Groups', "$TOPDIR/machines/groups.php"),
			'nodes' => array('Nodes', "$TOPDIR/machines/nodes.php"),
			'layout' => array('Layout', "$TOPDIR/machines/layout.php")
		));
	}
	elseif ($currents[0] == 'jobs') {
		insertMenuRow($currents[1], 0, array(
			'overview' => array('Overview', "$TOPDIR/jobs/overview.php"),
			//todo:  Vallard fill in rest
		));
	}
	elseif ($currents[0] == 'deploy') {
		insertMenuRow($currents[1], 0, array(
			'osimages' => array('OS Images', "$TOPDIR/deploy/osimages.php"),
			'prepare' => array('Prepare', "$TOPDIR/deploy/prepare.php"),
			'deploy' => array('Deploy', "$TOPDIR/deploy/deploy.php"),
			'monitor' => array('Monitor', "$TOPDIR/deploy/monitor.php"),
		));
	}
	elseif ($currents[0] == 'config') {
		insertMenuRow($currents[1], 0, array(
			'prefs' => array('Preferences', "$TOPDIR/config/prefs.php"),
			'site' => array('Cluster Settings', "$TOPDIR/config/site.php"),
			'mgmtnode' => array('Mgmt Node', "$TOPDIR/config/mgmtnode.php"),
			'monitor' => array('Monitor Setup', "$TOPDIR/config/monitor.php"),
			'eventlog' => array('Event Log', "$TOPDIR/config/eventlog.php"),
		));
	}
	elseif ($currents[0] == 'support') {
		insertMenuRow($currents[1], 0, array(
			'diagnose' => array('Diagnose', "$TOPDIR/support/diagnose.php"),
			'update' => array('Update', "$TOPDIR/support/update.php"),
			'howtos' => array('HowTos', "$TOPDIR/support/howtos.php"),
			'manpages' => array('Man Pages', "$TOPDIR/support/manpages.php"),
			'maillist' => array('Mail List', "http://xcat.org/mailman/listinfo/xcat-user"),
			'wiki' => array('Wiki', "http://xcat.wiki.sourceforge.net/"),
			'suggest' => array('Suggestions', "$TOPDIR/support/suggest.php"),
			'about' => array('About', "$TOPDIR/support/about.php"),
		));
	}
	echo "</table>\n";
}


// Insert one set of choices under a main choice.
function insertMenuRow($current, $isTop, $items) {
	global $TOPDIR;
	//$img = "$TOPDIR/images/h3bg_new.gif";
	$menuRowClass = $isTop ? '' : 'class=MenuRowBottom';
	$menuItemClass = $isTop ? 'class=MenuItemTop' : '';
	$currentClass = $isTop ? 'class=CurrentMenuItemTop' : '';

	//echo "<TABLE class=MenuTable id=mainNav cellpadding=0 cellspacing=0 border=0><tr>\n";
	//echo "<div class=$menuRowClass><ul id=mainNav>\n";
	echo "<tr><td $menuRowClass><ul id=mainNav>\n";

	foreach ($items as $key => $link) {
		if ($key == $current){
			//echo "<TD><a id=$key href='$link[1]'>$link[0]</a></TD>\n";
			echo "<li><p $currentClass>$link[0]</p></li>";
		} else {
			//echo "<TD><a class=NavItem id=$key href='$link[1]'>$link[0]</a></TD>\n";
			echo "<li><a $menuItemClass id=$key href='$link[1]'>$link[0]</a></li>";
		}
	}

	//echo "</TR></TABLE>\n";
	//echo "</ul></div>\n";
	echo "</td></tr></ul>\n";
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
			 -1: Like mode 1
			  3: Long running cmd. Results/errors are output to a file and return a file handle to the caller function
		3. Reference variable to hold the output returned to caller function
		4. Reference to an options hash, e.g. { NoVerbose => 1, NoRedirectStderr => 1 }
	Return status: 0 - successful, error - 1
------------------------------------------------------------------------------------------------*/
function runcmd ($cmd, $mode, &$output, $options=NULL){

	//Set error output to the same source as standard output (on Linux)
	if (strstr($cmd,'2>&1') == FALSE && !$options["NoRedirectStdErr"]) { $cmd .= ' 2>&1'; }
	$cmd = "/bin/sudo $cmd";      //todo: change this when move to xcat 2

	$ret_stat = "";
	$arr_output = NULL;
	if ($mode == 3){
		$handle = popen($cmd, "r");
		if($handle){
			$output = $handle;	//return file handle to caller
			return 0;	//successful
		}else{
			echo "Piping command into a file failed";
			return 1;
		}
	}elseif ($mode == 0 || $mode == 2 ){
		exec($cmd,$arr_output,$ret_stat);
		if ($ret_stat == 0){
			$output = $arr_output;
		} else {
			//output the error msg to the screen
			if ($mode == 0)	echo $arr_output[0];
			//output error msg to the caller function
			elseif ($mode == 2) $output = $arr_output[0];
		}
	}elseif ($mode == 1 || $mode == -1){
		system($cmd,$ret_stat);
	}
	return $ret_stat;
}


// Send the keys and values in the primary global arrays
function dumpGlobals() { //------------------------------------
	trace('$_SERVER:');
	foreach ($_SERVER as $key => $val) { trace("$key = $val"); }
	trace('<br>$_ENV:');
	foreach ($_ENV as $key => $val) { trace("$key = $val"); }
	trace('<br>$_REQUEST:');
	foreach ($_REQUEST as $key => $val) { trace("$key = $val"); }
	if (isset($_SESSION)) {

		trace('<br>$_SESSION:');
		foreach ($_SESSION as $key => $val) { trace("$key = $val"); }
	}
}

# Returns true if the given rpm file is already installed at this version or higher.
function isInstalled($rpmfile) { //------------------------------------
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



// Debug output  ------------------------------------
define("TRACE", "1");
function trace($str) { if (TRACE) { echo "<p class=Trace>$str</p>\n"; } }


// Take in a hostname or ip address and return the fully qualified primary hostname.  If resolution fails,
// it just returns what it was given.
function resolveHost($host) { //------------------------------------
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

//------------------------------------
function isIPAddr ($host) { return preg_match('/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/', $host); }


// Returns the URL for the requested documentation.  This provides 1 level of indirection in case the location
// of some of the documentation changes.
function getDocURL($book, $section) { //------------------------------------
	$web = array (
		   'docs' => "http://xcat.org/doc",
		   'forum' => "http://xcat.org/mailman/listinfo/xcat-user",
		   'updates' => "http://www.alphaworks.ibm.com/tech/xCAT",
		   'opensrc' => "http://www-rcf.usc.edu/~garrick",
		   'wiki' => "http://www.asianlinux.org/xcat",
		   );
	$man = array ();
	$howto = array ();
	$rsctadmin = array (
				0 => "http://publib.boulder.ibm.com/infocenter/clresctr/vxrx/topic/com.ibm.cluster.rsct.doc/rsct_aix5l53",
				1 => "$rsctadmin[0]/bl5adm1002.html",
				 'sqlExpressions' => "$rsctadmin[0]/bl5adm1042.html#ussexp",
				 'conditions' => "$rsctadmin[0]/bl5adm1041.html#cmrcond",
				 'responses' => "$rsctadmin[0]/bl5adm1041.html#cmrresp",
				 'resourceClasses' => "$rsctadmin[0]/bl5adm1039.html#lavrc",
				);

	$rsctref = array (
				0 => "http://publib.boulder.ibm.com/infocenter/clresctr/vxrx/topic/com.ibm.cluster.rsct.doc/rsct_linux151",
				1 => "$rsctref[0]/bl5trl1002.html",
			   'errm' => "$rsctref[0]/bl5trl1067.html#errmcmd",
			   'errmScripts' => "$rsctref[0]/bl5trl1081.html#errmscr",
			   'sensor' => "$rsctref[0]/bl5trl1088.html#srmcmd",
			   'auditlog' => "$rsctref[0]/bl5trl1095.html#audcmd",
			   'lscondresp' => "$rsctref[0]/bl5trl1071.html#lscondresp",
			   'startcondresp' => "$rsctref[0]/bl5trl1079.html#startcondresp",
			  );

	if ($book) {
		if (!$section) { $section = 1; }     // link to whole book if no section specified
		$url = &$$book;
		return $url[$section];
	}
	else {          // produce html for a page that contains all the links above, for testing purposes
		return '';        //todo:
	}
}


// This returns important display info about each type of hardware, so we can easily add new hw types.
function getHWTypeInfo($hwtype, $attr) { //------------------------------------
	//todo: get the aliases to be keys in this hash too
	$hwhash = array (
			  'x335' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8676' ),
			  'x336' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8837' ),
			  'x306' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8836' ),
			  'x306m' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8849,8491' ),
			  'x3550' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7978' ),
			  'e325' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8835' ),
			  'e326' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'8848' ),
			  'e326m' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'7969' ),
			  'e327' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'' ),

			  'x340' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8656' ),
			  'x342' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8669' ),
			  'x345' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8670' ),
			  'x346' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'8840' ),
			  'x3650' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'7979' ),

			  'x360' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8686' ),
			  'x365' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8862' ),
			  'x366' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8863' ),
			  'x3850' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'8863' ),
			  'x445' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
			  'x450' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
			  'x455' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
			  'x460' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),
			  'x3950' => array ( 'image'=>'342.gif', 'rackimage'=>'x366-front', 'u'=>3, 'aliases'=>'' ),

			  'hs20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8678,8843,7981' ),   # removed 8832 because it is older and it made this entry to wide in the drop down boxes
			  'js20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8842' ),
			  'js21' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8844' ),
			  'ls20' => array ( 'image'=>'blade.gif', 'rackimage'=>'blade-front', 'u'=>7, 'aliases'=>'8850' ),
			  'hs40' => array ( 'image'=>'blade2.gif', 'rackimage'=>'blade2-front', 'u'=>7, 'aliases'=>'8839' ),

			  'p5-505' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'9115' ),
			  'p5-505Q' => array ( 'image'=>'330.gif', 'rackimage'=>'x335-front', 'u'=>1, 'aliases'=>'9115' ),

			  'p5-510' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9110' ),
			  'p5-510Q' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9110' ),
			  'p5-575' => array ( 'image'=>'342.gif', 'rackimage'=>'x345-front', 'u'=>2, 'aliases'=>'9118' ),

			  'p5-520' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9111' ),
			  'p5-520Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9131' ),
			  'p5-550' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9113' ),
			  'p5-550Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9133' ),
			  'p5-560' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9116' ),
			  'p5-560Q' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9116' ),
			  'p5-570' => array ( 'image'=>'520.gif', 'rackimage'=>'p5-520-front', 'u'=>4, 'aliases'=>'9117' ),

			  'p5-590' => array ( 'image'=>'590.gif', 'rackimage'=>'p5-590-front', 'u'=>42, 'aliases'=>'9119' ),
			  'p5-595' => array ( 'image'=>'590.gif', 'rackimage'=>'p5-590-front', 'u'=>42, 'aliases'=>'9119' ),

			  'p710' => array ( 'image'=>'342.gif', 'rackimage'=>'x335-front', 'u'=>2, 'aliases'=>'9123' ),
			  'p720' => array ( 'image'=>'520.gif', 'rackimage'=>'x345-front', 'u'=>4, 'aliases'=>'9124' ),

			  'p610' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>5, 'aliases'=>'7028' ),
			  'p615' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>4, 'aliases'=>'7029' ),
			  'p630' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>4, 'aliases'=>'7026' ),
			  'p640' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>5, 'aliases'=>'7026' ),
			  'p650' => array ( 'image'=>'520.gif', 'rackimage'=>'x335-front', 'u'=>8, 'aliases'=>'7038' ),
			  'p655' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'7039' ),
			  'p670' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'7040' ),
			  'p690' => array ( 'image'=>'590.gif', 'rackimage'=>'x335-front', 'u'=>42, 'aliases'=>'7040' ),
			 );
	$info = $hwhash[strtolower($hwtype)];
	if (isset($attr)) { return $info[$attr]; }
	else { return $info; }
}


// Returns the image that should be displayed for this type of hw.  Gets this from getHWTypeInfo()
function getHWTypeImage($hwtype, $powermethod) { //------------------------------------
	# 1st try to match the hw type
	$info = getHWTypeInfo($hwtype, 'image');
	if ($info) { return $info['image']; }

	# No matches yet.  Use the power method to get a generic type.
	if (isset($powermethod)) {
		$powermethod = strtolower($powermethod);
	  if ($powermethod == 'blade') { return getHWTypeInfo('hs20', 'image'); }
	  elseif ($powermethod == 'hmc') { return getHWTypeInfo('p5-520', 'image'); }
	  elseif ($powermethod == 'bmc') { return getHWTypeInfo('x335','image'); }
	  elseif ($powermethod == 'xseries') { return getHWTypeInfo('x335', 'image'); }
	}

	# As a last resort, return the most common node image
	return getHWTypeInfo('x335', 'image');
}


// Return the image that represents the status string passed in
function getStatusImage($status) {
	global $TOPDIR;
	if ($status == 'good') { return "$TOPDIR/images/green-ball-m.gif"; }
	elseif ($status == 'warning') { return "$TOPDIR/images/yellow-ball-m.gif"; }
	elseif ($status == 'bad') { return "$TOPDIR/images/red-ball-m.gif"; }
	else { return "$TOPDIR/images/blue-ball-m.gif"; }
}


// Returns the specified user preference value.  Not finished.
function getPref($key) { //------------------------------------
	if ($key == 'MaxNodesDisplayed') { return 50; }
	return '';
}


// Returns a list of some or all of the nodes in the cluster and some of their attributes.
// Pass in a node range (or NULL to get all nodes) and an array of attribute names (or NULL for none).
// Returns an array where each key is the node name and each value is an array of attr/value pairs.
function getNodes($noderange, $attrs) {
	//my ($hostname, $type, $osname, $distro, $version, $mode, $status, $conport, $hcp, $nodeid, $pmethod, $location, $comment) = split(/:\|:/, $na);
	//$nodes[] = array('hostname'=>"node$i.cluster.com", 'type'=>'x3655', 'osname'=>'Linux', 'distro'=>'RedHat', 'version'=>'4.5', 'status'=>1, 'conport'=>$i, 'hcp'=>"node$i-bmc.cluster.com", 'nodeid'=>'', 'pmethod'=>'bmc', 'location'=>"frame=1 u=$", 'comment'=>'');
	$nodes = array();
	foreach ($attrs as $a) {
		$output = array();
		//echo "<p>nodels $noderange $a</p>\n";
		runcmd("nodels $noderange $a", 2, $output);
		foreach ($output as $line) {
			$vals = preg_split('/: */', $line);   // vals[0] will be the node name
			if (!$nodes[$vals[0]]) { $nodes[$vals[0]] = array(); }
			$attributes = & $nodes[$vals[0]];
			if ($a == 'type') {
				$types = preg_split('/-/', $vals[1]);
				$attributes['osversion'] = $types[0];
				$attributes['arch'] = $types[1];
				$attributes['type'] = $types[2];
			}
		}
	}
	return $nodes;
}


// Returns the node groups defined in the cluster.
function getGroups() {
	$groups = array();
	$output = array();
	runcmd("listattr", 2, $output);
	foreach ($output as $grp) { $groups[] = $grp; }
	return $groups;
}


// Returns the aggregate status of each node group in the cluster.  The return value is a
// hash in which the key is the group name and the value is the status as returned by nodestat.
function getGroupStatus() {
	$groups = array();
	$output = array();
	runcmd("grpattr", 2, $output);
	foreach ($output as $line) {
		//echo "<p>line=$line</p>";
		$vals = preg_split('/: */', $line);
		if (count($vals) == 2) { $groups[$vals[0]] = $vals[1]; }
	}
	return $groups;
}

// Returns true if we are running on AIX ------------------------------------
function isAIX() { }     //todo: implement

// Returns true if we are running on Linux ------------------------------------
function isLinux() { }     //todo: implement

// Returns true if we are running on Windows ------------------------------------
function isWindows() { return array_key_exists('WINDIR', $_SERVER); }


// Create file folder-like tabs.  Tablist is an array of label/url pairs.
function insertTabs ($tablist, $currentTabIndex) { //------------------------------------
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


// Create the Action buttons in a table.  Buttonlist is an array of arrays of button attribute strings.
function insertButtons ($buttonsets) { //------------------------------------
	foreach ($buttonsets as $buttonlist) {
		echo "<TABLE cellpadding=0 cellspacing=2><TR>";
		foreach ($buttonlist as $button) {
			//echo "<td><INPUT type=submit class=but $button ></td>";
			echo "<td><a class=button href=''><span>$button</span></a></td>";
			}
		echo "</TR></TABLE>\n";
	}
}


function insertNotDoneYet() { echo "<p class=NotDone>This page is not done yet.</p>\n"; }

?>

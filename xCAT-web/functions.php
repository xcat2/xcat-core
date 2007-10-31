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
function insertHeader($title, $stylesheets, $javascripts) {
global $TOPDIR;
if (!$TOPDIR) 	$TOPDIR = '.';
?>

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title><?php echo $title; ?></title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">
<link rel="stylesheet" href="style.css">
<link rel="stylesheet" href="menu.css">
<script type="text/javascript" src="functions.js"></script>

<script type="text/javascript" src="js_xcat/event.js"> </script>
<script type="text/javascript" src="js_xcat/ui.js"> </script>

<!-- These are only needed for popup windows, so only need it for specific pages like dsh
<script type="text/javascript" src="javascripts/prototype.js"> </script>
<script type="text/javascript" src="javascripts/effect.js"> </script>
<script type="text/javascript" src="javascripts/window.js"> </script>
<link href="themes/default.css" rel="stylesheet" type="text/css"/>
-->

<link rel="stylesheet" href="css/xcattop.css">
<link rel="stylesheet" href="css/xcat.css">
<link rel="stylesheet" href="css/clickTree.css">
<script src="js/windows.js" type="text/javascript"></script>
<script src="js/clickTree.js" type="text/javascript"></script>
<script src="js/prototype.js" type="text/javascript"></script>
<script src="js/scriptaculous.js" type="text/javascript"></script>
<script src="js/xcat.js" type="text/javascript"></script>

<?php
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
?>
</head>
<body>
<table border=0 align=left cellspacing=0 cellpadding=0>
<tr>
    <td><img src="images/xCAT_icon.gif"></td>
    <td background="images/header_bg.gif" width=700>
    	<p id=banner>xCAT - e<u>x</u>treme <u>C</u>luster <u>A</u>dministration <u>T</u>ool</p>
    	<p id=disclaimer>This interface is still under construction and not yet ready for use.</p>
    </td>
</tr>
</table>
<?php }  // end insertHeader


// A few constants
/*
require_once("lib/config.php");
$config = &Config::getInstance();
$imagedir = $config->getValue("IMAGEDIR");
$colTxt = "Click to collapse section";
$exTxt = "Click to expand section";
$bulgif = "$imagedir/h3bg_new.gif";
$minusgif = "$imagedir/minus-sign.gif";
$plusgif = "$imagedir/plus-sign.gif";
*/


/*------------------------------------------------------------------------------
   Create the navigation area on the left.
   $currentlink is the key of the link to the page
   that is currently being displayed.
------------------------------------------------------------------------------*/

function insertNav($currentLink) {
// A few constants
global $TOPDIR;    // or could use $GLOBALS['TOPDIR']
$colTxt = "Click to collapse section";
$exTxt = "Click to expand section";
$bulgif = "$TOPDIR/images/h3bg_new.gif";
$minusgif = "$TOPDIR/images/minus-sign.gif";
$plusgif = "$TOPDIR/images/plus-sign.gif";

echo '<div id=nav><table border="0" cellpadding="0" cellspacing="1" width="70">';

//Console section
insertInner('open', 1,'Console', 'constab', $currentLink, array(
	'prefs' => array("$TOPDIR/prefs.php", 'Preferences'),
	'updategui' => array("$TOPDIR/softmaint/updategui.php", 'Update'),
	'suggestions' => array("$TOPDIR/suggestions.html", 'Suggestions'),
	'logout' => array("$TOPDIR/logout.php", 'Logout')
));

// xCAT Cluster section
?>
 <TR><TD id="menu_level1">
 <P title="<?php echo $colTxt; ?>" onclick="toggleSection(this,'clustab')" ondblclick="toggleSection(this,'clustab')">
 <IMG src=<?php echo $minusgif ?> id='clustab-im'> xCAT Cluster
 </P></TD></TR>
 <TR><TD>
  <TABLE id='clustab' cellpadding=0 cellspacing=0 width="100%"><TBODY>
    <TR><TD id="menu_level3"><A href="csmconfig"><IMG src='<?php echo "$TOPDIR/images/h3bg_new.gif" ?>'>&nbsp;Settings</A></TD></TR>

<?php
	insertInner('open', 2,'Installation', 'installtab', $currentLink, array(
		'softmaint' => array("$TOPDIR/softmaint", 'MS Software'),
		'addnodes' => array("$TOPDIR/addnodes.php", 'Add Nodes'),
		'definenode' => array("$TOPDIR/definenode.php", 'Define Nodes'),
		'hwctrl' => array("$TOPDIR/hwctrl/index.php", 'HW Control')
	));
	insertInner('open', 2,'Administration', 'admintab', $currentLink, array(
		'nodes' => array("$TOPDIR/index.php", 'Nodes'),
		'layout' => array("$TOPDIR/hwctrl/layout.php", 'Layout'),
		'dsh' => array("$TOPDIR/dsh.php", 'Run Cmds'),
		'dcp' => array("$TOPDIR/dcp.php", 'Copy Files'),
		'cfm' => array("$TOPDIR/cfm.php", 'Sync Files'),
		'shell' => array("$TOPDIR/shell.php", 'Cmd on MS'),
		'import' => array("$TOPDIR/import.php", 'Import/Export'),
	));
	insertInner('open', 2,'Monitor', 'montab', $currentLink, array(
		'conditions' => array("$TOPDIR/mon", 'Conditions'),
		'responses' => array("$TOPDIR/mon/resp.php", 'Responses'),
		'sensors' => array("$TOPDIR/mon/sensor.php", 'Sensors'),
		'rmcclass' => array("$TOPDIR/mon/rmcclass.php", 'RMC Classes'),
		'auditlog' => array("$TOPDIR/mon/auditlog.php", 'Event Log'),
		'perfmon' => array("$TOPDIR/perfmon/index.php", 'Performance'),

	));
	insertInner('open', 2,'Diagnostics', 'diagtab', $currentLink, array(
		'diagms' => array("$TOPDIR/diagms", 'MS Diags'),
	));

  echo '</TABLE></TD></TR>';

insertInner('open', 1,'Documentation', 'doctab', $currentLink, array(
	'xcatdocs' => array(getDocURL('web','docs'), 'xCAT Docs'),
	'forum' => array(getDocURL('web','forum'), 'Mailing List'),
	'codeupdates' => array(getDocURL('web','updates'), 'Code Updates'),
	'opensrc' => array(getDocURL('web','opensrc'), 'Open Src Reqs'),
	'wiki' => array(getDocURL('web','wiki'), 'xCAT Wiki'),
));

echo '</table></div>';
}  //end insertNav


/**--------------------------------------------------------------
	Insert one inner table in the nav area function above.
	Type is the type of the menu item, i.e: close or open (plus sign/minus sign)
	Level is the level of the parent menu item (can be first or second)
	Id is the id property of the table.
	CurrentLink is the key of the link for the current page.
	List is a keyed array of href, label pairs.
----------------------------------------------------------------*/
function insertInner($type,$level,$title, $id, $currentLink, $list) {
// A few constants
global $TOPDIR;    // or could use $GLOBALS['TOPDIR']
$colTxt = "Click to collapse section";
$exTxt = "Click to expand section";
$bulgif = "$TOPDIR/images/h3bg_new.gif";
$minusgif = "$TOPDIR/images/minus-sign.gif";
$plusgif = "$TOPDIR/images/plus-sign.gif";

	switch($level){
		case 1: $menu_level = "menu_level1"; break;
		case 2: $menu_level = "menu_level2"; break;
		default: $menu_level = "menu_level1";
	}
	if ($type == "open"){
		$gif = $minusgif;
		$hoverTxt = $colTxt;
		$style = "display:inline";
	}else {
		$gif = $plusgif;
		$hoverTxt = $exTxt;
		$style = "display:none";
	}
?>
<TR><TD id=<?php echo $menu_level; ?>>
<P title="<?php echo $hoverTxt; ?>" onclick="toggleSection(this,'<?php echo $id ?>')" ondblclick="toggleSection(this,'<?php echo $id ?>')">
<IMG src=<?php echo $gif; ?> id=<?php echo $id."-im" ?>> <?php echo $title ?></P></TD></TR>
<TR><TD >
<TABLE id=<?php echo $id ?> width="100%" cellpadding="0" cellspacing="0" border=0 style=<?php echo $style ?>>

<?php

foreach ($list as $key => $link) {
	if ($key == $currentLink){
		echo "<TR><TD id='menu_level3' class='current'><IMG src='$TOPDIR/images/h3bg_new.gif'>&nbsp;$link[1]</TD></TR>\n";
	}else{
		echo "<TR><TD id='menu_level3'><A href='$link[0]'><IMG src='$TOPDIR/images/h3bg_new.gif'>&nbsp;$link[1]</A></TD></TR>\n";
	}
}
?>
</TABLE></TD></TR>

<?php }//end insertInner


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
	if (strstr($cmd,'2>&1') == FALSE && !$options["NoRedirectStdErr"])
		$cmd .= ' 2>&1';

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
	$lang = isWindows() ? '' : 'LANG=C';
	$rc = runcmd("$lang /bin/rpm -U $aixrpmopt --test $rpmfile", 2, $out);
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


// Returns the specified user preference value.  Not finished.
function getPref($key) { //------------------------------------
	if ($key == 'MaxNodesDisplayed') { return 50; }
	return '';
}


// Returns a list of some or all of the nodes in the cluster.  Pass in either a group name or node range,
// or NULL for each to get all nodes.  Not finished.
function getNodes($group, $noderange) { //------------------------------------
	//my ($hostname, $type, $osname, $distro, $version, $mode, $status, $conport, $hcp, $nodeid, $pmethod, $location, $comment) = split(/:\|:/, $na);
	for ($i = 1; $i <= 10; $i++) {
		$nodes[] = array('hostname'=>"node$i.cluster.com", 'type'=>'x3655', 'osname'=>'Linux', 'distro'=>'RedHat', 'version'=>'4.5', 'status'=>1,
						'conport'=>$i, 'hcp'=>"node$i-bmc.cluster.com", 'nodeid'=>'', 'pmethod'=>'bmc', 'location'=>"frame=1 u=$", 'comment'=>'');
	}
	return $nodes;
}


// Returns the node groups defined in the cluster.  Not finished.
function getGroups() { //------------------------------------
	return array('AllNodes','group1','group2');
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
			echo "<TD align=center background='images/tab-current.gif'><b>$tab[0]</b></TD>";
			}
		else {
			echo "<TD align=center background='images/tab.gif'><A href='$tab[1]'>$tab[0]</A></TD>";
			}
	}
    echo "</TR><TR><TD colspan=7 height=7 bgcolor='#CBCBCB'></TD></TR></TBODY></TABLE>\n";
}


// Create the Action buttons in a table.  Buttonlist is an array of arrays of button attribute strings.
function insertButtons ($buttonsets) { //------------------------------------
	foreach ($buttonsets as $buttonlist) {
		echo "<TABLE cellpadding=0 cellspacing=2><TBODY><TR><TD nowrap>";
		foreach ($buttonlist as $button) { echo "<INPUT type=submit class=but $button >"; }
		echo "</TD></TR></TBODY></TABLE>\n";
	}
}


?>

<?php
if(!isset($TOPDIR)) { $TOPDIR='.';}
require_once "$TOPDIR/lib/security.php";

function displayHeader() {
echo <<<EOS1
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="en">
<head>
<title>xCAT</title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">
<link rel="stylesheet" type="text/css" href="css/main.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/superfish.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/security.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/config.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/monitor.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/theme/jquery-ui-1.7.2.custom.css" media="screen">
<link rel="stylesheet" type="text/css" href="js/jsTree/tree_component.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/demo_page.css" media="screen">
<link rel="stylesheet" type="text/css" href="css/demo_table.css" media="screen">
<script type="text/javascript" src="js/jquery.min.js"></script>
<script type="text/javascript" src="js/jquery-ui-all.min.js"></script>
<script type="text/javascript" src="js/loading.js"></script>
</head>
EOS1;

#<script type="text/javascript" src="js/jquery.min.js"></script>
#<!-- for noderange tree -->
#<script type="text/javascript" src="js/jsTree/jquery.listen.js"></script>
#<script type="text/javascript" src="js/jsTree/tree_component.js"></script>
#<script type="text/javascript" src="js/jsTree/jquery.cookie.js"></script>
#<script type="text/javascript" src="js/noderangetree.js"></script>
#<script type="text/javascript" src="js/jsTree/css.js"></script>
#<!-- for various forms -->
#<script type="text/javascript" src="js/jquery.form.js"></script>
#<!-- for editing xCAT tables -->
#<script type="text/javascript" src="js/jquery.jeditable.mini.js"></script>
#<!-- for menus -->
#<script type="text/javascript" src="js/hoverIntent.js"></script>
#<!-- for menus -->
#<script type="text/javascript" src="js/superfish.js"></script>
#<!-- for authentication -->
#<script type="text/javascript" src="js/jquery-ui-all.min.js"></script>
#<!-- for tying all these libraries together  -->
#<script type="text/javascript" src="js/xcat.js"></script>
#<!-- for authentication  -->
#<script type="text/javascript" src="js/xcatauth.js"></script>
#<script type="text/javascript" src="js/config.js"></script>
#<script type="text/javascript" type"utf-8">
#	$(document).ready(function() {
#		injs();
#	});
#</script> 
#</head>

}


function displayBody() {

echo <<<EOS2
<body onload="xStart()">
 <div id="loadingZone">
	xCAT<br>
  <div id="loadingSms">LOADING</div>  
         <div id="infoProgress">0%</div>  
         <br class="clear" />  
         <div id="loadingBar">  
             <div id="progressBar">&nbsp;</div>  
         </div>  
         <div id="infoLoading"></div>  
 </div>
 <div id="wrapper">

 <div id=header>
  <ul class="sf-menu" id='sf-menu'>
   <li>
        <img src="img/logo.gif" height=100% onclick='loadMainPage("index.php")'/>
   </li>
   <li>
    <a href="control.php">control</a>
	<ul>
	<li><a href="vm.php">VM Management</a></li>
	</ul>
   </li>
   <li class="current">
    <a href="config.php">configure</a>
        <ul>
        <li><a href="#" onclick='loadLLCfgEditor()'>LoadLeveler</a></li>
        </ul>
EOS2;
   # 	echo "<ul>\n";
#	$tables = getTabNames();
#	$j = 0;
#	foreach($tables as $t){
#		$j++;
#		if($j < 13){
#			echo "<li><a href='config.php?t=$t''>$t</a></li>";
#		}elseif($j < 25){
#			echo "<li class=level2><a href='config.php?t=$t''>$t</a></li>";
#		}else{
#			echo "<li class=level3><a href='config.php?t=$t''>$t</a></li>";
#		}
#	}
#	echo "</ul>\n";
echo <<<EOS4
   </li>
   <li>
    <a href="provision.php">provision</a>
   </li>
   <li>
    <a href="monitor/monlist.php">monitor</a>
	<ul>
   		<li>
    			<a href="monitor.php">syslog</a>
   		</li>
                <li>
                        <a href="monitor/rmc_monshow.php">Resource Performance</a>
                </li>
                <li>
                        <a href="monitor/rmc_lsevent.php">RMC Events</a>
                </li>
	</ul>
   </li>
   <li>
        <a href="help.php">Help</a>
        <ul>
            <li><a href="update.php">Update</a></li>
            <li><a href="summary.php">Summary</a></li>
        </ul>
   </li>
  </ul>
  <!-- <div id="cmdForm">
    <form action="command.php" method="post" id="runcmd">
        <input type="text" size="19" id="cmd" value="run xCAT command"/>
        <input type="image" src="img/cmdBtn.gif" id='go' alt="Run xCAT command" title="run xCAT command">
    </form>
  </div> -->
  <div id='musername'>
EOS4;
	echo "user: <span> " . $_SESSION["username"] . "</span>";
echo <<<EOS5
	<br>
	<a href="#" onclick='logout()'>log out</a>
  </div>
 </div>
 <div id='topper'>&nbsp;
 </div>
 <div id='main'>
     &nbsp;
 </div>
EOS5;

}

function displayFooter() {
echo "<div id='bopper'>&nbsp;</div>";
//<div id='footer'>xCAT Web v2.2.06242009</div>
# use system() to get the xCAT Web version;
echo "<div id='footer'>";
system("rpm -q xCAT-UI");
echo "</div>";
# comment out if statement to fix refresh but of logout.
	if(!isAuthenticated()){
		insertLogin();
	}

echo <<<EOS3
 </div> <!-- finishes off the wrapper div -->
</body>
</html>
EOS3;


}

// Create the bread crumb links.  The mapper arg is a hash of label/url pairs, where
// the final url is usually ''.
function displayMapper($mapper)
{
    echo "<div class=mapper><span>";
    $first = 1;
    foreach ($mapper as $key => $value) {
    	if (!$first) { echo " / "; }
    	$first = 0;
    	if (!strlen($value)) { echo $key; }
    	else {
    		if ($value == 'main.php') { $href = '#'; }
    		else { $href = "#$value"; }
        	echo "<a href='$href' onclick='loadMainPage(\"$value\")'>$key</a>";
    	}
    }
    echo "</span></div>";
}

function displayTabMain(){
displayMapper(array('home'=>'main.php', 'config' =>''));
/*
echo <<<MAPPER
<div class='mapper'>
	<span>
		<a href='#' onclick='loadMainPage("main.php")'>home</a> / 
		config
	</span>
</div>
MAPPER;
*/
echo <<<EOS
<div class='mContent'>
<h1>Configuration Menu</h1>
xCAT is configured by several tables.  Each of the tables below
tweeks a setting in xCAT.  Click on a table below to configure xCAT
EOS;

	$xml = docmd('tabdump', '', array('-d'));
	foreach($xml->children() as $response) foreach($response->children() as $line){
		list($tabName, $descr) = split(":", $line, 2);	
		echo "<p><a href='#' onclick='loadConfigTab(\"$tabName\");return false;'>$tabName</a>$descr</p>\n";	
	}

echo <<<EOS
</div>
EOS;
}

function displayTab($tab){
displayMapper(array('home'=>'main.php', 'config' =>'config.php', "$tab"=>''));
/*
	echo <<<MAPPER
<div class='mapper'>
	<span>
		<a href='#' onclick='loadMainPage("main.php")'>home</a> / 
		<a href='#config.php' onclick='loadMainPage("config.php")'>config</a> / 
		$tab
	</span>
</div>
MAPPER;
*/
	echo "<div class='mContent'>";
	echo "<h1>$tab</h1>\n";
	insertButtons(array('label' => 'Save','id' => 'saveit'),
			array('label' => 'Cancel', 'id' => 'reset')
		);
	$xml = docmd('tabdump', '', array($tab));
	$headers = getTabHeaders($xml);
	if(!is_array($headers)){ die("<p>Can't find header line in $tab</p>"); }
	echo "<table id='tabTable' class='tabTable' cellspacing='1'>\n";
	#echo "<table class='tablesorter' cellspacing='1'>\n";
	echo "<thead>";
	echo "<tr class='colHeaders'><td></td>\n"; # extra cell for the red x
	#echo "<tr><td></td>\n"; # extra cell for the red x
	foreach($headers as $colHead) {echo "<td>$colHead</td>"; }
	echo "</tr>\n"; # close header row

	echo "</thead><tbody>";
	$tableWidth = count($headers);
	$ooe = 0;
	$item = 0;
	$line = 0;
	$editable = array();
	foreach($xml->children() as $response) foreach($response->children() as $arr){
		$arr = (string) $arr;
		if(ereg("^#", $arr)){
			$editable[$line++][$item] = $arr;
			continue;
		}
		$cl = "ListLine$ooe";
		$values = splitTableFields($arr);
		# X row
		echo "<tr class=$cl id=row$line><td class=Xcell><a class=Xlink title='Delete row'><img class=Ximg src=img/red-x2-light.gif></a></td>";
		foreach($values as $v){
			echo "<td class=editme id='$line-$item'>$v</td>";
			$editable[$line][$item++] = $v;
		}
		echo "</tr>\n";
		$line++;
		$item = 0;
		$ooe = 1 - $ooe;
	}
	echo "</tbody></table>\n";
	$_SESSION["editable-$tab"] = & $editable; # save the array so we can access it in the next call of this file or change.php
	echo "<p>";
insertButtons(array('label' => 'Add Row', 'id' => 'newrow'));
echo "</p>\n";
?>
<script type="text/javascript">
  //jQuery(document).ready(function() {
  makeEditable('<?php echo $tab ?>', '.editme', '.Ximg', '.Xlink');

  // Set up global vars to pass to the newrow button
  document.linenum = <?php echo $line ?>;
  document.ooe = <?php echo $ooe ?>;

  $("#reset").click(function(){
    alert('You sure you want to discard changes?');
    $('#main').load("config.php?t=<?php echo $tab ?>&kill=1");
    });

  $("#newrow").click(function(){
    var newrow = formRow(document.linenum, <?php echo $tableWidth ?>, document.ooe);
    document.linenum++;
    document.ooe = 1 - document.ooe;
    $('#tabTable').append($(newrow));
    makeEditable('<?php echo $tab ?>', '.editme2', '.Ximg2', '.Xlink2');
  });
  $("#saveit").click(function(){
    $('#main').load("config.php?t=<?php echo $tab ?>&save=1", {
    indicator : "<img src='img/indicator.gif'>",
    });
  });

// $("table").tablesorter({
 //                       sortList: [[0,0]]
  //              });
</script>


<?php
}

//-----------------------------------------------------------------------------
// Create the Action buttons in a table.  Each argument passed in is a button, which is an array of attribute strings.
// If your onclick attribute contains javascript code that uses quotes, use double quotes instead of single quotes.
function insertButtons () {
	$num = func_num_args();
	#if ($num > 1) echo "<TABLE cellpadding=0 cellspacing=2><TR>";
  foreach (func_get_args() as $button) {
		$otherattrs = @$button['otherattrs'];
		$id = @$button['id'];
		if (!empty($id)) { $id = "id=$id"; } 
		$onclick = @$button['onclick'];
		if (!empty($onclick)) { $onclick = "onclick='$onclick'"; }
	#	if ($num > 1) echo "<td>";
		echo "<a class=button $id $onclick $otherattrs><span>{$button['label']}</span></a>";
	#	if ($num > 1) echo "</td>";
	}
	#if ($num > 1) echo "</TR></TABLE>\n"; I hate tables!!!
}

// $errors should be an array with errors
function displayErrors($errors){
	echo "<p class=Error>Changes to table failed! ", implode(' ',$errors), ",</p>\n"; 
}

function displaySuccess($tab){
	echo "<p class=Info>Changes to $tab have been saved.</p>\n";
}

function displayAlert($a){
echo <<<EOS7
<script type="text/javascript" type"utf-8">
	alert('hi!' + '$a');
</script>
EOS7;

}


// Functions to control display of trees and control functions

function displayCtrlPage($cmd){
displayMapper(array('home'=>'main.php', 'control' =>''));
	echo "<div class='nrcmd'>";
	echo "<div id='nrcmdnoderange'>Noderange:</div>";
	echo "<div id='nrcmdcmd'>Action: $cmd</div>";
	echo "</div>\n";
	echo "</div>\n";

	//displayControlTables($cmd);
}
	


function displayNrTree(){
echo <<<EOS
<div id=nrtree style='width:27%'></div>
<div id='rangedisplay' class='mContent' style='width:70%'><h1>Please select a node or noderange on the left.</h1>
<p>You can use ctrl-click to select more than one node grouping, </p>
<p>or expand the noderanges to select individual nodes.</p></div>
<script type="text/javascript" type"utf-8">
	initTree();
</script>
EOS;
}

function displayControlTables($cmd){
	echo <<<EOSS
<ul class='controlHeaders'>
	<li id='ctrl-power'><a href='#'>Power</a></li>
	<li id='ctrl-inv'><a href='#'>Inventory</a></li>
	<li id='ctrl-env'><a href='#'>Environmentals</a></li>
	<li id='ctrl-event'><a href='#'>Event Logs</a></li>
	<li id='ctrl-beacon'><a href='#'>Beacon Light</a></li>
</ul>
EOSS;

}

function displayRangeList($nr, $cmd){
    echo "<div style='width:95%'>";
	if($cmd == ""){
		displayCommands($nr);
		return;
	}
	if(substr($cmd,0,6) == 'rpower'){
		$array = explode('rpower', $cmd);
		controlRunCmd($nr, 'rpower', $array[1]);
	}elseif(substr($cmd,0,4) == 'rinv'){
		$array = explode('rinv', $cmd);
		controlRunCmd($nr, 'rinv', $array[1]);
	}elseif(substr($cmd,0,7) == 'rvitals'){
		$array = explode('rvitals', $cmd);
		controlRunCmd($nr, 'rvitals', $array[1]);
	}elseif(substr($cmd,0,7) == 'rbeacon'){
		$array = explode('rbeacon', $cmd);
		controlRunCmd($nr, 'rbeacon', $array[1]);
	}else{
		echo "I don't recognize the command: $cmd";
	}
    echo "</div>";
}

function displayCommands($nr){
	echo <<<EOF
<h1>Please select an action to perform on noderange <i>$nr</i></h1>
<h2>Power</h2>
<ul>
	<li><a href='#' onclick='controlCmd("rpoweroff","$nr")'>Power Off</a></li>
	<li><a href="#" onclick='controlCmd("rpoweron","$nr")'>Power On</a></li>
	<li><a href="#" onclick='controlCmd("rpowerboot","$nr")'>Reboot</a></li>
	<li><a href='#' onclick='controlCmd("rpowerstat","$nr")'>Power Status</a></li>
</ul>
<h2>Inventory</h2>
<ul>
	<li><a href='#' onclick='controlCmd("rinvall","$nr")'>Display All Inventory</a></li>
	<li><a href='#' onclick='controlCmd("rinvvpd","$nr")'>Vital Product Data</a></li>
	<li><a href='#' onclick='controlCmd("rinvmprom","$nr")'>MPROM</a></li>
</ul>
<h2>Vitals</h2>
<ul>
	<li><a href='#' onclick='controlCmd("rvitalsall","$nr")'>All Vital Information</a></li>
	<li><a href='#' onclick='controlCmd("rvitalstemp","$nr")'>Tempterature</a></li>
	<li><a href='#' onclick='controlCmd("rvitalswattage","$nr")'>Wattage</a></li>
	<li><a href='#' onclick='controlCmd("rvitalsvoltage","$nr")'>Voltage</a></li>
	<li><a href='#' onclick='controlCmd("rvitalsfanspeed","$nr")'>Fan Speeds</a></li>
	<li><a href='#' onclick='controlCmd("rvitalspower","$nr")'>Power Usage</a></li>
	<li><a href='#' onclick='controlCmd("rvitalsleds","$nr")'>LEDs</a></li>
</ul>
<h2>Beacon</h2>
<ul>
	<li><a href='#' onclick='controlCmd("rbeaconstat","$nr" )'>Get Beacon Light Status</a></li>
	<li><a href='#' onclick='controlCmd("rbeaconoff","$nr")'>Turn Beacon Light Off</a></li>
	<li><a href='#' onclick='controlCmd("rbeaconon","$nr")'>Turn Beacon Light On</a></li>
</ul>
<h2>Remote Commands</h2>
<ul>
	<li>Run a command on all nodes</li>
</ul>
<h2>Event Log</h2>
<ul>
	<li>View Event Log</li>
	<li>Clear Event Log</li>
</ul>
<h2>Set Boot Order</h2>
<ul>
	<li>Set Boot Order</li>
</ul>

EOF;
}

function controlRunCmd($nr, $cmd, $subcmd){
echo <<<JS00
<script type="text/javascript" type"utf-8">
$(document).ready(function() {
    $("#tableForCtrl").dataTable({
        "bLengthChange": true,
        "bFilter": true,
        "bSort": true,
        "iDisplayLength": 50
    });
});
</script>
JS00;
    echo "<div id=tableForCtrl>";
    $rvals = docmd($cmd, $nr, array($subcmd));
    #print_r($rvals);
    $headers = attributesOfNodes($rvals,$cmd);
    #echo "<br><br>Headers:<br>";
	#print_r($headers);
    $nh = mkNodeHash($rvals,$cmd);
    #echo "<br><br><br>";
    echo "<table style='width:100%'>";
    echo "<thead>";
    echo "<tr>";
    echo "<th>Node</th>";
    foreach ($headers as $head){
            echo "<th>$head</th>";
    }
    echo "</tr>";
    echo "</thead><tbody>";
    foreach($nh as $n => $vals){
            echo "<tr>\n";
            #echo "<td class='$cl'>$n</td>";
            echo "<td>$n</td>";
            foreach($headers as $h){
                    if($vals[$h] == ''){
                            echo "&nbsp;";
                    }else{
                            #echo "<td class='$cl'>" . $vals[$h] . "</td>";
                            echo "<td>" . $vals[$h] . "</td>";
                    }
            }
            echo "</tr>";
    }
    echo "</tbody>";
    echo "</table>";
    echo "</div>";

}


// Main page display

function displayMainPage() {

echo <<<EOS
<div class='mContent'>
<!-- <h1>Wizards</h1>
<ul>
	<li>Initial xCAT Configuration</li>
	<li>Create a new image</li>
	<li>Set up Monitoring</li>
</ul>
-->
<h1><a href='#' onclick='loadMainPage("control.php")'>Control</a></h1>
<ul>
	<li>Power nodes off/on</li>
	<li>Collect hardware information</li>
	<li>Run Command on All Nodes</li>
</ul>
<h1><a href='#' onclick='loadMainPage("config.php")'>Configure</a></h1>
<ul>
    <li>Edit xCAT Tables</li>
</ul>
EOS;
#	echo "<ul>";
#	$tables = getTabNames();
#	foreach($tables as $t){
#		echo "<li><a href='#' onclick='loadTab(\"$t\")'>$t</a></li>";
#	}
#	echo "</ul>";
echo <<<EOS
<h1><a href='#' onclick='loadMainPage("provision.php")'>Provision</a></h1>
<ul>
	<li>Provision node</li>
</ul>
<h1><a href='#' onclick='loadMainPage("monitor.php")'>Syslog</a></h1>
<ul>
    <li>Show syslog Entries</li>
</ul>
<h1><a href='#' onclick='loadMainPage("monitor/monlist.php")'>Monitor</a></h1>
<ul>
    <li>Set up xCAT Monitoring Plug-in</a></li>
    <li>This is still <b>UNDER DEVELOPMENT</b>.</li>
</ul>
</div>
EOS;
}


// Monitoring page stuff.  Right now its just the syslog monitor


function displayLogTable(){
	if(($line = getLastLine('')) === 0){
		return;
	};
displayMapper(array('home'=>'main.php', 'syslog' =>''));
echo <<<EOS
<div class='mContent'>
<h1>Syslog Entries</h1>
<a href="#" id="stop">Stop Updates</a> | 
<a href="#" id="start">Start Updates</a><br><br>
<table class="tablesorter" cellspacing="1">
	<thead>
		<tr>
			<th>Date</th>
			<th>Time</th>
			<th>Host</th>
			<th>SubSystem</th>
			<th>Message</th>
		</tr>
	</thead>
	<tbody>
EOS;
	$time = logToTable($line);
echo <<<EOS
	</tbody>
</table>
</div>
<script type="text/javascript" type"utf-8">
 $("table").tablesorter({ sortList:  [[0,1],[1,1]] });
 tableUpdater(0,'');
 $("#stop").click(function() { clearTimeout(t); });
 $("#start").click(function() { tableUpdater(0,''); });
</script>
EOS;

}

// Given a Line from Syslog formats into a table.
function logToTable($line){
	list($month,$date,$time,$host,$subsys,$message) = preg_split('/\s+/', $line, 6);  
	if($message == ''){
		echo "no entry";
		return;
	}
	echo <<<EOS
<tr>
<td>$month $date</td>
<td>$time</td>
<td>$host</td>
EOS;

if($subsys == 'last'){
	$message = $subsys . " " . $message;
	$subsys = "&nbsp";
}

echo <<<FOO
<td>$subsys</td>
<td>$message</td>
</tr>
FOO;
	return;
}

// provision page stuff
## here is where we provision nodes.
# m - method (install or netboot)
# o - OS (centos5.3, etc)
# a - arch (x86, x86_64)
# p - profile (compute, or user defined)
function displayProvisionPage($m,$o,$a,$p){
displayMapper(array('home'=>'main.php', 'provision' =>''));
	echo "<div class='nrcmd'>";
	echo "<div id='nrcmdnoderange'>Noderange:</div>";
	echo "<div id='nrcmdos'>Operating System: $o</div>";
	echo "<div id='nrcmdarch'>Architecture: $a</div>";
	echo "<div id='nrcmdmethod'>Install Method: $m</div>";
	echo "<div id='nrcmdprofile'>Profile: $p</div>";
	echo "</div>\n";
	echo "</div>\n";
}

function displayInstallList($nr, $m,$o,$a,$p){
	if($m == ""){
		displayProvisionOps($nr);
		return;
	}
	echo "installing $m $o $a $p<br>";
}

function displayProvisionOps($nr){
	echo <<<EOF
<div id='part1'>
<h1>Please select an OS to install on the noderange <i>$nr</i></h1>
	<select id='os' onchange='changeOS()'>
		<option value=""></option>
		<option value="centos5.3">CentOS 5.3</option>
		<option value="centos5.2">CentOS 5.2</option>
		<option value="fedora10">Fedora 10</option>
		<option value="fedora9">Fedora 9</option>
		<option value="fedora8">Fedora 8</option>
		<option value="rhels5.3">Red Hat Linux 5.3</option>
		<option value="rhels5.2">Red Hat Linux 5.2</option>
		<option value="sles10.2">SUSE Enterprise Linux (SLES) 10 update 2</option>
		<option value="sles10.1">SUSE Enterprise Linux (SLES) 10 update 1</option>
		<option value="rh">VMWare ESX 3.5</option>
		<option value="esxi4">VMWare ESXi 4.0</option>
		<option value="win2k8">Windows Server 2008</option>
	</select>
</div>
<div id='part2' style='display:none'>
<h1>Please select the architecture</h1>
	<select id='arch' onchange='changeArch()'>
		<option value=''></option>
		<option value='x86_64'>x86_64 (EMT64 or AMD64)</option>
		<option value='x86'>x86 (i686, etc)</option>
		<option value='ppc64'>ppc64</option>
	</select>
</div>
<div id='part3' style='display:none'>
<h1>How do you want to install the noderange <i>$nr</i></h1>
	<select id='method' onchange='changeMeth()'>
		<option value=""></option>
		<option value='netboot'>Stateless/Netboot Image</option>
		<option value='install'>Stateful Traditional Install (e.g: kickstart/autoyast)</option>
	</select>
</div>
<div id='part4' style='display:none'></div>
<div id='part5' style='display:none'></div>
<div id='part6' style='display:none'></div>

EOF;
}


function getHostName() {
    if($_SERVER['SERVER_SOFTWARE'] == 'IBM_HTTP_Server') {
        return exec("hostname");
    }else {
        return exec("hostname --long");
    }
}

function getCPUInfo() {
    #check the var $_SERVER['SERVER_SOFTWARE'] to determine the server's os type
    #if its value is "IBM_HTTP_Server", the server will be treated as AIX
    if($_SERVER['SERVER_SOFTWARE'] == 'IBM_HTTP_Server') {
        return exec("lscfg -vp |wc -l");#on AIX, the command can show processor count
    }else {
        return exec("cat /proc/cpuinfo |grep -i processor |wc -l");
    }
}

function getMemInfo() {
    if($_SERVER['SERVER_SOFTWARE'] == 'IBM_HTTP_Server') {#AIX
        $str = exec("lsattr -El sys0 |grep realmem");
        $arr = preg_split('/\s+/', $str);
        return $arr[1];
    }else {
        $str = exec("cat /proc/meminfo |grep MemTotal");
        $arr = preg_split('/[:\s]+/', $str);
        return $arr[1];
    }
}

function getNetworksInfo() {
    #the command is "lsdef -t network -i net,mask,mgtifname" in the sever end;
    #display the net, mask and mgtifname in one small table
    echo "<table id=mgmt_network cellspacing=5 >";
    echo "<thead>";
    echo "<tr><th>Network</th><th>Netmask</th><th>MgtIfName</th></tr>";
    echo "</thead>";
    echo "<tbody>";
    $xml = docmd("tabdump", "", array("networks"));
    foreach($xml->children() as $response) foreach($response->children() as $data) {
        if(strstr($data[0], '#') != FALSE) { continue; }
        else {
            #print_r($data);
            $arr = split(",", $data);
            echo "<tr>";
            echo "<td>".$arr[1]."</td>";
            echo "<td>".$arr[2]."</td>";
            echo "<td>".$arr[3]."</td>";
            echo "</tr>";
        }
    }
    echo "</tbody>";
    echo "</table>";
}

function summary_general() {
    $hostname = getHostName();
    $cpus = getCPUInfo();
    $mem = getMemInfo();
    #TODO
echo <<<INFO0
       <table>
        <tbody>
        <tr>
        <td bgcolor="#cccccc">Hostname</td>
        <td>$hostname</td>
        </tr>
        <tr>
        <td bgcolor="#cccccc">Processors</td>
        <td>$cpus</td>
        </tr>
        <tr>
        <td bgcolor="#cccccc">Memory</td>
        <td>$mem KB</td>
        </tr>
        <tr>
        <td bgcolor="#cccccc">Networks</td>
        <td>
INFO0;
    getNetworksInfo();
echo <<<INFO1
        </td>
        </tr>
        </tbody>
        </table>
INFO1;
}

/*
 * showNodeStat()
 * will show the number of nodes in the cluster
 * and also show their status
 */

function showNodeStat() {
    $xml=docmd("rpower", "all", array("stat"));
    $stat_arr = array();
    foreach($xml->children() as $response){
        #parse the xml tree
        #print_r($response);
        if($response->errorcode == 0) {
            #echo $response->node->name, $response->node->data->contents;
            $key = $response->node->name;
            $stat_arr["$key"] = $response->node->data->contents;
        }
    }
    echo "<div>";
    echo "<div style='width:40%; margin-left:64px'>";
    echo "<table id=rpowerstat_num>";
    $stat_num = array("Operating" => 0, "Running" => 0, "Not Activated" => 0, "Open Firmware" => 0);
    foreach ($stat_arr as $k => $v) {
        $stat_num["$v"] ++;
    }
    echo "<tr><td>Operating</td><td>", $stat_num["Operating"], "</td></tr>";
    echo "<tr><td>Running</td><td>",$stat_num["Running"],"</td></tr>";
    echo "<tr><td>Not Activated</td><td>",$stat_num["Not Activated"],"</td></tr>";
    echo "<tr><td>Open Firmware</td><td>",$stat_num["Open Firmware"],"</td></tr>";
    echo "</table>";
    #add two buttons here: show/hide the detailed status in stat_table <table>
    #TODO: move them to the proper positions 
    echo "<div class='fg-buttonset fg-buttonset-single' style='margin-left:30px'>";
    echo "<button id='show' class='fg-button ui-state-default ui-state-active ui-priority-primary ui-corner-left'>Show</button>";
    echo "<button id='hide' class='fg-button ui-state-default ui-corner-right'>Hide</button>";
    echo "</div>";
    echo "</div>";
echo <<<GRAPH0
<script type="text/javascript">
    $(function() {
        $("#show").click(function() {
            if($(this).is(".ui-state-active")) {
                loadNodeStatus();
                $(this).removeClass("ui-state-active");
                $("#hide").addClass("ui-state-active");
            }
        });
        $("#hide").click(function() {
            if($(this).is(".ui-state-active")) {
                $("#p_stat_table").hide();
                $(this).removeClass("ui-state-active");
                $("#show").addClass("ui-state-active");
            }
        });
    });
    /*
    var data=[
        {label: "Operating", data: 3 },
        {label: "Running", data: 4 },
        {label: "Not Activated", data: 12 },
        {label: "Open Firmware", data: 1 }
    ];
    */
    var options = {
        series: {
            pie: {
                show: true
            }
        }
    };
    $.ajax({
        url: "rpowerstat.php",
        type: 'POST',
        data: "type=json",
        dataType: 'json',
        success: function(data) {
            $.plot($("#chart0"), data, options);
        }
    });
    /*
    "rpowerstat.php", {type:"json"}, function(data) {
        $.plot($("#chart0"), data, options);
    });
    */

</script>
<div id='chart0' style="width:65%;height:256px;float: right">
</div>
GRAPH0;
    echo "</div>";
    echo "<div id='p_stat_table' style='border: 1px solid #AAA; width: 95%; float: right'>";
    echo "<div id='stat_table'></div>";
    echo "</div>";
    echo "<div class='spacer'></div>";
}


/* showMonSum()
 * will show the summary information of monitor plugins.
 * 
 */

function showMonSum() {
    $xml = docmd("monls", "", array("-a"));

    echo "<div> ";
    #print_r($xml);
    echo "<table id='monplugin_list' style='margin-left: 30px'>";
    echo "<thead><tr><th>Plugins</th><th>Status</th><th>NodeStatSupport</th><th></th></tr></thead>";
    echo "<tbody>";

    foreach($xml->children() as $response)  foreach($response->children() as $data){
            list($name, $stat, $nodemon) = preg_split("/\s+/", $data);
            echo "<tr>";
            echo "<td>$name</td><td>$stat</td>";
            if($nodemon) {
                echo "<td>Enabled</td>";
            }else {
                echo "<td>Disabled</td>";
            }
            echo "<td><button class='fg-button ui-state-active'>MonShow</button></td>";
            echo "</tr>";
    }

    echo "</tbody>";
    echo "</table>";
    echo "</div>";
}

function showxCATInfo() {
    echo "<div>";
    #$ret = shell_exec("rpm -qa |grep xCAT");/* there's no newline character in the string */
    /*
     *  xCAT-UI-2.4-snap200912080702
        xCAT-client-2.4-snap200912180657
        perl-xCAT-2.4-snap200912240801
        xCAT-rmc-2.4-snap200912051911
        xCAT-2.4-snap200912240802
        xCAT-server-2.4-snap200912190921
     *
     */
    #$rpms = preg_split("/\n/", $ret);
    echo "<table id=rpmtable style='margin-left: 30px'>";
    $ret = shell_exec("rpm -q xCAT");
    if($ret) {
        $verstr = substr($ret, 5);
        echo "<tr>";
        echo "<td>xCAT</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    $ret = shell_exec("rpm -q xCAT-server");
    if($ret) {
        $verstr = substr($ret, 12);
        echo "<tr>";
        echo "<td>xCAT-server</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    $ret = shell_exec("rpm -q xCAT-client");
    if($ret) {
        $verstr = substr($ret, 12);
        echo "<tr>";
        echo "<td>xCAT-client</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    $ret = shell_exec("rpm -q perl-xCAT");
    if($ret) {
        $verstr = substr($ret, 10);
        echo "<tr>";
        echo "<td>perl-xCAT</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    $ret = shell_exec("rpm -q xCAT-rmc");
    if($ret) {
        $verstr = substr($ret,9);
        echo "<tr>";
        echo "<td>xCAT-rmc</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    $ret = shell_exec("rpm -q xCAT-UI");
    if($ret) {
        $verstr = substr($ret,8);
        echo "<tr>";
        echo "<td>xCAT-UI</td><td>$verstr</td><td></td>";
        echo "</tr>";
    }
    echo '</table>';
    echo "</div>";
}

function showUpdateRow($RpmName){
    $ret = shell_exec("rpm -q " . $RpmName);

    $aRpm = explode("\n",$ret);
    foreach ($aRpm as $TempRpm)
    {
        if($TempRpm){
            $verstr= substr($TempRpm, strlen($RpmName) + 1);
            echo ("<tr>");
            echo ("<td><input type=\"checkbox\" value=\"" . $RpmName . "\"></td>");
            echo ("<td>" . $RpmName . "</td>");
            echo ("<td>" . $verstr . "</td>");
            echo ("</tr>");
        }
    }
}


function showUpdateInfo() {
    echo "<div><table id=rpmtable style='margin-left: 30px'>";
    echo "<tr>";
    echo "<td><input type=\"checkbox\" id=\"selectall\" value=\"\" onclick=\"fun_js_select_all()\"></td>";
    echo "<td>Package Name</td>";
    echo "<td>Version</td>";
    echo "</tr>";

    showUpdateRow("xCAT-client");
    showUpdateRow("perl-xCAT");
    showUpdateRow("xCAT-server");
    showUpdateRow("xCAT");
    showUpdateRow("xCAT-rmc");
    showUpdateRow("xCAT-UI");

    echo '</table></div>';
}
?>

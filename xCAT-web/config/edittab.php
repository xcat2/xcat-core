<?php
// Display/edit a single table from the xcat db.  This is call via a jQuery load() call.

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

if(isset($_REQUEST['tab'])) { $tab = $_REQUEST['tab']; }
else { echo "<p>No table name specified. Please specify a table to edit.</p>\n"; exit; }

//echo "<p>" . implode(',',array_keys($_SESSION)) . "</p>\n";
//if (array_key_exists("editable-$tab",$_SESSION)) { echo "<p>count=".count($_SESSION["editable-$tab"])."</p>\n"; }

if(isset($_REQUEST['kill'])) {
	unset($_SESSION["editable-$tab"]);
}

if(isset($_REQUEST['save'])) {
	$rsp = doTabrestore($tab,$_SESSION["editable-$tab"]);
	$errors = array();
	if (getXmlErrors($rsp,$errors)) { echo "<p class=Error>Tabrestore failed: ", implode(' ',$errors), "</p>\n"; }
	else { echo "<p class=Info>Changes have been saved.</p>\n"; }
}

// Get table contents
//$f = splitTableFields2('"node01","node02","5000","off",,'); echo '<p>'; foreach ($f as $k => $v) { echo "$k=$v<br>"; } echo "</p>\n";
echo "<h1>$tab Table</h1>";
echo "<table border=0><tr><td rowspan=2>", getTabDescription($tab), "</td>\n";
echo "<td><a href='" . getDocURL('dbtable',$tab) . "' target='_blank'>Column Descriptions</a></td></tr>\n";
echo "<tr><td><a href='" . getDocURL('dbtable') . "' target='_blank'>Regular Expression Support</a></td></tr></table>\n";

// Display the column names
$xml = docmd('tabdump','',array($tab));
$headers = getTabHeaders($xml);
if(!is_array($headers)){ die("<p>Can't find header line in $tab</p>"); }
echo "<table id=tabTable>\n";
echo "<tr class='colHeaders'><td></td>\n";		// extra cell is for the red x
foreach($headers as $colHead) { echo "<td>$colHead</td>"; }
echo "</tr>\n"; # close header row

// Save the width of the table for adding a new row when they click that button
$tableWidth = count($headers);

// Display table contents and remember its contents in a session variable.
$ooe = 0;		// alternates the background of the table
$item = 0;		// the column #
$line = 0;
$editable = array();
foreach ($xml->children() as $response) foreach ($response->children() as $arr){
	$arr = (string) $arr;
	if(ereg("^#", $arr)){		// handle the header specially
		$editable[$line++][$item] = $arr;
		continue;
	}
	$cl = "ListLine$ooe";
	$values = splitTableFields($arr);
	// If you change this line, be sure to change the formRow function in db.js
	echo "<tr class=$cl id=row$line><td class=Xcell><a class=Xlink title='Delete row'><img class=Ximg src=$TOPDIR/images/red-x2-light.gif></a></td>";
	foreach($values as $v){
		//$v = preg_replace('/\"/','', $v);
		echo "<td class=editme id='$line-$item'>$v</td>";
		$editable[$line][$item++] = $v;
	}
	echo "</tr>\n";
	$line++;
	$item = 0;
	$ooe = 1 - $ooe;
}
echo "</table>\n";
$_SESSION["editable-$tab"] = & $editable;		// save the array so we can access it in the next call of this file or change.php
//unset($_SESSION["editable-$tab"]);

insertButtons(array('label' => 'Add Row', 'id' => 'newrow'),
			array('label' => 'Save', 'id' => 'saveit'),
			array('label' => 'Cancel', 'id' => 'reset')
			);
?>


<script type="text/javascript">
	//jQuery(document).ready(function() {
	makeEditable('<?php echo $tab ?>', '.editme', '.Ximg', '.Xlink');

	// Set up global vars to pass to the newrow button
	document.linenum = <?php echo $line ?>;
	document.ooe = <?php echo $ooe ?>;

	// Set actions for buttons
	$("#reset").click(function(){
		//alert('You sure you want to discard changes?');
		$('#middlepane').load("edittab.php?tab=<?php echo $tab ?>&kill=1");
		});
	$("#newrow").click(function(){
		var newrow = formRow(document.linenum, <?php echo $tableWidth ?>, document.ooe);
		document.linenum++;
		document.ooe = 1 - document.ooe;
		$('#tabTable').append($(newrow));
		makeEditable('<?php echo $tab ?>', '.editme2', '.Ximg2', '.Xlink2');
	});
	$("#saveit").click(function(){
		$('#middlepane').load("edittab.php?tab=<?php echo $tab ?>&save=1", {
		indicator : "<img src='../images/indicator.gif'>",
		});
	});
	//});
</script>

<?php

//-----------------------------------------------------------------------------
function getTabHeaders($xml){
	foreach ($xml->children() as $response) foreach ($response->children() as $line) {
		$line = (string) $line;
		if (ereg("^#", $line)) {
			$line = preg_replace('/^#/','', $line);
			$headers = explode(',', $line);
			return $headers;
		}
	}
	// If we get here, we never found the header line
	return NULL;
}


//-----------------------------------------------------------------------------
function getTabDescription($tab) {
	$xml = docmd('tabdump','',array('-d'));
	foreach ($xml->children() as $response) foreach ($response->children() as $line) {
		$line = (string) $line;
		if (ereg("^$tab:",$line)) {
			$line = preg_replace("/^$tab:\s*/", '', $line);
			return $line;
		}
	}
	return '';
}

?>
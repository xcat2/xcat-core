<?php

// Display/edit tables in the xcat db

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('xCAT Database', array('db.css'),
			array('db.js',"$TOPDIR/jq/jquery.jeditable.mini.js"),
			array('config','db'));

echo "<div id=content align=center>\n";

// Display all the table links
echo "<div id=tableNames><h3>Tables</h3>\n";
$tables = getTabNames();
foreach ($tables as $t) {
	//if ($i++ > 7) { echo "</tr>\n<tr>"; $i = 1; }
	echo "<a href='#$t'>$t</a> ";
}
echo "\n</div>\n";

if(isset($_REQUEST['tab'])) { $tab = $_REQUEST['tab']; }
else { $tab = "nodelist"; }
$p = "edittab.php?tab=$tab";

echo "<div class=middlepane id=middlepane>Loading $tab ...</div>\n";
//echo "<div class=bottompane></div>\n";
echo "<script type='text/javascript'>\n";
echo " loadTable('$tab');";
echo " bindTableLinks();";
echo "\n</script>\n";


insertFooter();


//-----------------------------------------------------------------------------
// Return the list of database table names
function getTabNames() {
	$xml = docmd('tabdump','',NULL);
	$tabs = array();
	foreach ($xml->children() as $response) foreach ($response->children() as $t) { $tabs[] = (string) $t; }
	return $tabs;
}

?>

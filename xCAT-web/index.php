<?php

// Main page of the xCAT web interface, but will redirect to the default page

$TOPDIR = '.';
require_once "$TOPDIR/lib/functions.php";

// First try to get the cookie of the last visited page
if (isset($_COOKIE['currentpage'])) {
	//echo "<p>here</p>\n";
	$keys = $_COOKIE['currentpage'];
	$m = $MENU[$keys[0]];              // this gets us to the menu choice for the top menu in the data structure
	$url = $m['list'][$keys[1]]['url'];      // get to the list of submenu choices, choose the proper one, and get its url
	//echo "<p>url: $url, m[label]: " . $m['label'] . "</p>\n";
} else { $url = 'machines/groups.php'; }

header("Location: $url");

?>
<?php

// Allow the user to log out and log back in

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

logout();

insertHeader('Logout/Login', NULL, NULL, array('logout','logout'));

/*
dumpGlobals();

$xml = docmd("authcheck","",NULL);
echo "<p>authcheck:<br>\n";
foreach ($xml->children() as $response) foreach ($response->children() as $t) { echo (string) $t, "<br>\n"; }
echo "</p>\n";

$xml = docmd('tabdump','',NULL);
echo "<p>tabdump:<br>\n";
foreach ($xml->children() as $response) foreach ($response->children() as $t) { echo (string) $t, "<br>\n"; }
echo "</p>\n";
*/

//insertNotDoneYet();
insertFooter();
?>

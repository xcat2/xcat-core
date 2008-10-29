<?php

// Utilities to help diagnose problems in the cluster

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Diagnose', NULL, NULL, array('support','diagnose'));

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

insertNotDoneYet();
insertFooter();
?>

<?php
//setcookie("history", "", time() - 3600);  //to delete a cookie, but did not seem to work
$TOPDIR = '..';
require_once "../lib/functions.php";

echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">';
echo "<html><head>\n";
echo "<link href='../lib/style.css' rel=stylesheet type='text/css'>\n";
echo "</head><body>\n";

//insertLogin();

dumpGlobals();

/*
$xml = docmd("authcheck","",NULL);
echo "<p>authcheck:<br>\n";
foreach ($xml->children() as $response) foreach ($response->children() as $t) { echo (string) $t, "<br>\n"; }
echo "</p>\n";

$xml = docmd('tabdump','',NULL);
echo "<p>tabdump:<br>\n";
foreach ($xml->children() as $response) foreach ($response->children() as $t) { echo (string) $t, "<br>\n"; }
echo "</p>\n";
*/

phpinfo();

echo "</body></html>\n";
?>
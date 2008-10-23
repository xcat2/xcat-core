<?php
//setcookie("history", "", time() - 3600);  //to delete a cookie, but did not seem to work
$TOPDIR = '..';
require_once "../lib/functions.php";

echo <<<EOS1
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>phpinfo</title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">
<link href="$TOPDIR/lib/style.css" rel=stylesheet type='text/css'>

<link href="$TOPDIR/jq/theme/jquery-ui-theme.css" rel=stylesheet type='text/css'>
<script src="$TOPDIR/jq/jquery.min.js" type="text/javascript"></script>
<script src="$TOPDIR/jq/jquery-ui-all.min.js" type="text/javascript"></script>
<script src="$TOPDIR/lib/functions.js" type="text/javascript"></script>

</head>
<body>

EOS1;

//insertLogin();
echo <<<EOS2
<script src="$TOPDIR/lib/xcatauth.js" type="text/javascript"></script>
<div id=logdialog>
<form id=loginform>
<label for=username>Username:</label><input id=username type=text name=username><br/>
<label for=password>Password:</label><input id=password type=password name=password></form>
<span class=logstatus id=logstatus><br/></span>
</div>

EOS2;

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

phpinfo();
*/

echo "</body></html>\n";
?>
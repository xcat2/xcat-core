<?php
//setcookie("history", "", time() - 3600);  //to delete a cookie, but did not seem to work
$TOPDIR = '..';
//require_once "../lib/functions.php";

echo <<<EOS1
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>phpinfo</title>
<meta http-equiv="Content-Type" content="application/xhtml+xml;  charset=iso-8859-1">

<link href="$TOPDIR/jq/theme/jquery-ui-themeroller.css" rel=stylesheet type='text/css'>
<script src="$TOPDIR/jq/jquery.min.js" type="text/javascript"></script>
<script src="$TOPDIR/jq/jquery-ui-all.min.js" type="text/javascript"></script>

</head>
<body>

EOS1;

echo <<<EOS
<div id=tabs>
	<ul>
		<li class="ui-tabs-nav-item"><a href="#fragment-1"><span>One</span></a></li>
		<li class="ui-tabs-nav-item"><a href="#fragment-2"><span>Two</span></a></li>
	</ul>
	<div id="fragment-1">
		<p>First tab is active by default</p>
	</div>
	<div id="fragment-2">
		<p>Lorem ipsum dolor sit amet, consectetuer adipiscing elit, sed diam nonummy nibh euismod tincidunt ut laoreet dolore magna aliquam erat volutpat.</p>
	</div>
</div>
<script type="text/javascript">
$(document).ready(function() { $("#tabs > ul").tabs(); } );
</script>

EOS;


//insertLogin();

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
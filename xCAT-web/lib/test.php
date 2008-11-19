<?php
error_reporting(E_ALL);
ini_set('display_errors', true);

if (!isset($_GET['iframe'])) {
echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">';
echo "<html><head>\n";
/*
  <script src="http://code.jquery.com/jquery-latest.js"></script>
  <!-- <link rel="stylesheet" href="http://dev.jquery.com/view/tags/ui/latest/themes/flora/flora.all.css" type="text/css" media="screen" title="Flora (Default)"> -->
<link href="../jq/theme/jquery-ui-themeroller.css" rel=stylesheet type='text/css'>
  <script type="text/javascript" src="http://dev.jquery.com/view/tags/ui/latest/ui/ui.core.js"></script>
  <script type="text/javascript" src="http://dev.jquery.com/view/tags/ui/latest/ui/ui.tabs.js"></script>
*/
echo "</head><body>\n";

$a = array('a', 'b', 'c');
$b = array('d', 'e');
$c = array_merge($a, $b);
echo "<p>"; print_r($c); echo "</p>\n";

$d = array('f');
echo "<p>implode(a):", implode(',',$a), ".</p>\n";
echo "<p>implode(d):", implode(',',$d), ".</p>\n";

$var2 = @$somevar;
echo "<p>unset var is:", $var2, ".</p>\n";

//echo "<script type='text/javascript'>window.myfunvar='abc';function myfun() {alert('In myfun():'+window.myfunvar+'!');}</script>";
//echo "<p>adfasd asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf</p>\n";
//echo "<iframe src='test.php?iframe=1' width='100%' height=600></iframe>\n";
//echo "<object data='test.php?iframe=1' width='100%' height=600></object>\n";
echo "</body></html>\n";
}
else {
for ($i=1; $i<=2; $i++) {
	sleep(1);
	echo "<p>Line $i adfasd asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf asdf ads fasdf asdf asdf asdf asdf asdf asdf asfd asdf asdf asdf asdf asdf asdf asdf adsf asdf asdf asd ff asdf adsf asdf asdf asdf asdf asd f</p>\n";
	ob_flush(); flush();
	}
echo "<script type='text/javascript'>parent.myfun();</script>";
}
?>
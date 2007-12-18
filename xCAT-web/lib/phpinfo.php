<?php
//setcookie("history", "", time() - 3600);  //to delete a cookie, but did not seem to work
require_once "../lib/functions.php";

echo "<p>\n";
runcmd('echo $PATH', 1, $junk);
runcmd('whoami', 1, $junk);
echo "</p>\n";

/* $output = array(); runcmd("listattr", 2, $output); foreach ($output as $line) { echo "<p>line=$line</p>"; } */

phpinfo()
?>
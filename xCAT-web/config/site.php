<?php

// Display/change global settings in the site table

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Site', NULL, NULL, array('config','site'));
insertNotDoneYet();
echo '</body></html>';
?>

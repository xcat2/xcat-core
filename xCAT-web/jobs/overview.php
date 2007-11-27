<?php

// Manage OS images for deployment to nodes

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Jobs Overview', NULL, NULL, array('jobs','overview'));
insertNotDoneYet();
echo '</body></html>';
?>

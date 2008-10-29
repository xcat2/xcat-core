<?php

// Manage OS images for deployment to nodes

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Event Log', NULL, NULL, array('monitor','eventlog'));
insertNotDoneYet();
insertFooter();
?>

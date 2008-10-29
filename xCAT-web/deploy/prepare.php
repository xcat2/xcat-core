<?php

// Manage OS images for deployment to nodes

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Prepare Nodes for Deployment', NULL, NULL, array('deploy','prepare'));
insertNotDoneYet();
insertFooter();
?>

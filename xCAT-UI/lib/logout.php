<?php
/**
 * Allow the user to log out and log back in
 */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

logout();
header("Location: ../index.php");
?>

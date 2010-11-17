<?php
/**
 * Main xCAT page
 */
require_once "lib/functions.php";
require_once "lib/ui.php";
require_once "lib/jsonwrapper.php";

/* Load page */
loadPage();

/* Login user */
if (!isAuthenticated()) {
	login();
} else {
	loadContent();
}
?>
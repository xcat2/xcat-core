<?php
/**
 * Upload a given file into /var/tmp
 */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/jsonwrapper.php";

session_start();

if (!is_logged()) {
	echo "You are not logged in!";
	return;
}

// Set the file upload size limit (not sure if this actually works)
ini_set('upload_max_filesize', '4096M');
ini_set('post_max_size', '4096M');
ini_set('max_input_time', -1);

// Set time limit on how long this can run
set_time_limit(1200);

// Grab the target destination and file type
$dest =  $_GET["destination"];

// Only allow uploads onto /install
if (strcmp(substr($dest, 0, 9), "/install/") != 0) {
	echo "You are only authorized to upload onto /install subdirectories";
	return;
}

$file = $_FILES["file"]["name"];
$path = $dest . "/" . $file;
	
if (move_uploaded_file($_FILES["file"]["tmp_name"], $path)) {
	echo "File successfully uploaded";
	chmod($path, 0755);  // Change file to be executable
} else {
	echo "Failed to upload file to $path. ";
	
	// Obtain the reason for failure
	$reason = "";
	switch ($_FILES["file"]["error"]) {
		case 1:
			$reason = "The file is bigger than the PHP installation allows.";
			break;
		case 2:
			$reason = "The file is bigger than this form allows.";
			break;
		case 3:
			$reason = "Only part of the file was uploaded.";
			break;
		case 4:
			$reason = "No file was uploaded.";
			break;
		default:
			$reason = "Unknown error.";
	}
	
	echo $reason;
}
?>

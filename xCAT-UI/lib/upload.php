<?php
/**
 * Upload a given file into /var/tmp
 */
$type = $_FILES["file"]["type"];
if ($type == "text/plain" || $type == "application/octet-stream") {
	$error = $_FILES["file"]["error"];
	if ($error) {
		echo "Return Code: " . $error;
	} else {
		$file = $_FILES["file"]["name"];
		$path = "/var/tmp/" . $file;
		move_uploaded_file($_FILES["file"]["tmp_name"], $path);

		// Open and read given file
		$handler = fopen($path, "r");
		$data = fread($handler, filesize($path));
		fclose($handler);

		// Print out file contents
		echo $data;

		// Remove this file
		unlink($path);
	}
} else {
	echo "(Error) File type not supported";
}
?>
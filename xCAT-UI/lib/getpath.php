<?php
/**
 * Browse the server directory
 */
$path = $_POST["path"];
$result = array();

if(false && !isset($path)) {
	$element = array();
	$element["name"] = "Path should be specified";
	$element["isFolder"] = false;
	$element["isError"] = true;
	$result[$file] = $element;
	return;
} else {
	$path = $path.'/';
	$handle =  opendir($path);
	while (false !== ($file = readdir($handle))) {
		if ($file != "." && $file != "..") {
			$element = array();
			$element["name"] = $file;
			$element["isFolder"] = is_dir($path.$file);
			$element["isError"] = false;
			$result[$file] = $element;
		}
	}
}

echo json_encode($result);
?>
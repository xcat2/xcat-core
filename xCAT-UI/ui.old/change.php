<?php
// Modify the shadow copy of the table on the svr.
require_once "lib/functions.php";
/* $Id */
$tab = $_GET['tab'];

// Delete a row
if (isset($_GET['delrow'])) {
	$row = $_GET['delrow'];
	$editable = & $_SESSION["editable-$tab"];	# Get an easier alias for the table array
	unset($editable[$row]);
}

// Change a value in a cell
else {
	$id = $_POST['id'];
	$value =  $_POST['value'];

	$coord = array();
	$coord = explode('-', $id);
	$theLine = $coord[0];
	$theField = $coord[1];
	#echo "line: $theLine field: $theField<br>";

	# Get an easier alias for the table array
	$editable = & $_SESSION["editable-$tab"];

	# Modify the array with the new value from the editable widget
	$editable[$theLine][$theField] = $value;

	// This value goes back to the javascript editable object in the browser
	echo "$value";
}
?>

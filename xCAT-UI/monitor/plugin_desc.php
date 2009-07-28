<?php
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
?>
<?php
/*
 * Run the command "monls $name -d",
 * return the information
 */
# get the _REQUEST['name'] arguments
$name=$_REQUEST['name'];
$xml = docmd("monls"," ", array("$name", "-d"));

if (getXmlErrors($xml, $errors)) {
    echo "<p class=Error>monls failed: ", implode(' ',$errors), "</p>\n";
    exit;
}

$information = "";

foreach ($xml->children() as $response) foreach ($response->children() as $data) {
    $information .= str_replace("\n", "<br />", $data);;
    $information .= "\n<br/>";
    //print_r($data);
}
echo $information;
?>


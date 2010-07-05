<?php
/*
 * Created on 2010-6-3
 *
 * To change the template for this generated file go to
 * Window - Preferences - PHPeclipse - PHP - Code Templates
 */
require_once "lib/functions.php";
require_once "lib/security.php";
require_once "lib/display.php";

function checkRpmPath($sUrl)
{
    $hFileHandle = fopen($sUrl, 'r');
    if ($hFileHandle)
    {
        fclose($hFileHandle);
        return true;
    }
    else
    {
        return false;
    }
}

//check rpm_path & rpm_name in request
if(!isset($_REQUEST['repo']))
{
    echo "Please input a filepath.";
    exit;
}

if (!isset($_REQUEST['rpmname']))
{
    echo "Please select package.";
    exit;
}

$sRpmPath = $_REQUEST['repo'];
if ("" == $sRpmPath)
{
    echo "<label style=\"color:red\">Please input a filepath.</label>";
    exit;
}
$sRpmNames = $_REQUEST['rpmname'];
if ("" == $sRpmNames)
{
    echo "<label style=\"color:red\">Please select package.</label>";
    exit;
}

if (!checkRpmPath($sRpmPath))
{
    echo "<li style=\"color:red\">Repository Path Error!!</li>";
    echo "</ul></div>";
    return;
}

//set cookie must in front of any output
if (isset($_REQUEST["remember"]))
{
    setcookie("xcatrepository", $sRpmPath, time() + 864000, "/");
}
else
{
    setcookie("xcatrepository", "", time() - 172800, "/");
}

echo "<div class=\"mContent\">It will update <b>" . $sRpmNames ."</b> from <b>" . $sRpmPath . "</b>.<ul>";
echo "<li>Repository Path Check OK!</li>";

$Ret = docmd("webrun", array(), array("update", $sRpmNames, $sRpmPath));
var_dump($Ret);

echo "</ul></div>";
?>

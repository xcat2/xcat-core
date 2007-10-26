<?php

//Todo: get rid of the include path
// Set the include path
$APP_ROOT = dirname(__FILE__);
// Switch : to ; on Windows
ini_set('include_path', ini_get('include_path') . ":$APP_ROOT:$APP_ROOT/lib");

// The settings below display error on the screen, instead of giving blank pages.
error_reporting(E_ALL ^ E_NOTICE);
ini_set('display_errors', true);

require_once("lib/config.php");

// define global variables
$XCATROOT = getenv("XCATROOT") ? getenv("XCATROOT").'/bin' : '/opt/xcat/bin';
$SYSTEMROOT = '/bin';
$TOPDIR = '.';
$CURRDIR = '/opt/xcat/web';    //Todo: eliminate the need for this
$IMAGEDIR = "$TOPDIR/images";

// Put any configuration global variables here
// e.g. $config = &Config::getInstance();
//      $config->setValue("settingName", "settingValue");

$config = &Config::getInstance();
$config->setValue("XCATROOT", $XCATROOT);
$config->setValue("TOPDIR", $TOPDIR);
$config->setValue("CURRDIR", $CURRDIR);
$config->setValue("IMAGEDIR", $IMAGEDIR);
?>

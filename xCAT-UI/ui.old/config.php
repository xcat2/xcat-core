<?php
	require_once "lib/security.php";
	require_once "lib/functions.php";
	require_once "lib/display.php";
	if(isset($_REQUEST['t'])){
		$tab = $_REQUEST['t'];
		if(isset($_REQUEST['save'])){
			$rsp = doTabRestore($tab,$_SESSION["editable-$tab"]);
			$errors = array();
			if(getXmlErrors($rsp,$errors)){
				displayErrors($errors);
				dumpGlobals();
				exit();
			}else{
				displaySuccess($tab);
			}
		}
		elseif(isset($_REQUEST['kill'])){
			unset($_SESSION["edittable-$tab"]);
		}
		displayTab($tab);
		
	}else{
		displayTabMain();	
	}
	
?>

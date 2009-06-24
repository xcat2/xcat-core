<?php
	# this code is to list out the available profiles that a node 
	# can install in.  Its passed an install method (netboot or install)
	# and an OS and ARch.  It then lists out the profiles available in
	# /opt/xcat/share/xcat/<method>/<os>/
	# a user then selects these and is able to install a node.

	function displayProfiles($nr, $profiles){
		echo "<h1>Please select an install Template for <i>$nr</i></h1>";
		echo "<select id='prof' onchange='changeProf()'>";
		echo "<option value=''></option>";
		foreach($profiles as $prof){
			echo "<option value='$prof'>$prof</option>";
		}
		echo "</select>";
	}


	# m is the method 'netboot' or 'install'
	if(isset($_REQUEST['m'])){
		$method = $_REQUEST['m'];
	}
	# o is the os
	if(isset($_REQUEST['o'])){
		$os = $_REQUEST['o'];
	}
	# a is the architecture
	if(isset($_REQUEST['a'])){
		$arch = $_REQUEST['a'];
	}

	if(isset($_REQUEST['nr'])){
		$nr = $_REQUEST['nr'];
	}	
	# we need to format the path we're looking for:
	$path = "/opt/xcat/share/xcat/$method";
		
	# now we need to parse the OS:
	if(preg_match('/rh/',$os)){
		$path .= "/rh";
	}elseif(preg_match('/win2k8/',$os)){
		$path .= "/windows";
	}elseif(preg_match('/sles/',$os)){
		$path .= "/sles";
	}elseif(preg_match('/centos/',$os)){
		$path .= "/centos";
	}else{
		$path .= "/$os";
	}

	if($h = opendir($path)){
		$results = array();
		while ($file = readdir($h)){
			if(preg_match('/tmpl|pkglist/', $file)){
				$file = preg_replace('/.tmpl|.pkglist/','',$file);
				$results[] = $file;
			}
		}
		closedir($h);
	}
	if(empty($results)){
		echo "There don't appear to be any install templates in $path.<br>";
		echo "Please select a node range and start over.<br>";
	}
	displayProfiles($nr,$results);
?>

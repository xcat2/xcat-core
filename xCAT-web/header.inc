<?php
include "globals.inc";

function printMenu(){
	global $menuArray;
echo "<ul id='menubeans'>";
$p = 1;
foreach ($menuArray as $key => $value){
	if($p == 1){
		echo "<li class='active' id='$p' ><span>$key</span>\n";
		$p++;

	}else{
		echo "<li id='$p'><span>$key</span>\n";
		$p++;
	}
	echo "<ul>";
	$q = 0;
	foreach($value as $k => $u){
		if($p == 2){
			#echo "<li><a href=\"$u\" class='active'>$k</a></li>";
			echo "<li><a href='#' id='$p-li-$q' class='active' onClick=\"newBack('$u', 'content','$k', '$p-li-$q')\">$k</a></li>";
		}else{
			#echo "<li><a href=\"$u\">$k</a></li>";
			echo "<li><a href='#' id='$p-li-$q' onClick=\"newPane('$u', 'content', '$k', '$p-li-$q')\">$k</a></li>";
		}
		$q++;
	}
	echo "</ul>";
	echo "</li>";
}
echo "</ul>";
}

function printNodeList(){
	system("bin/getattrs --web");
}

?>

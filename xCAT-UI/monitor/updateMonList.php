<?php
/* 
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$xml = docmd("monls"," ", array('-a'));
 if(getXmlErrors($xml,$errors)) {
     echo "<p class=Error>",implode(' ', $errors), "</p>";
     exit;
 }
 #then, parse the xml data
 $ooe = 0;
 $line = 0;
 foreach($xml->children() as $response) foreach($response->children() as $data) {
     list($name, $stat, $nodemonstatus) = preg_split("/\s+/", $data);
     $ooe = $ooe%2;
     echo "<tr class='ListLine$ooe' id='row$line'>";
     echo "<td><input type='radio' name='plugins' value='$name' /></td>";
     echo "<td ><a class='description' href='#'>$name</a></td>";
     echo "<td >$stat</td>";
     if(isset($nodemonstatus)) { echo "<td >Enabled</td>";}else {echo "<td >Disabled</td>";}
     echo "<td>";
     $name_str = "\"$name\"";
     if($stat == "monitored") {
         $act_str = "\"stop\"";
         insertButtons(array('label'=>'Stop', 'id'=>'stop', 'onclick'=>"monsetupAction($name_str, $act_str)"));
         $act_str = "\"restart\"";
         insertButtons(array('label'=>'Restart', 'id'=>'restart', 'onclick'=>"monsetupAction($name_str, $act_str)"));
     }else {
         $act_str = "\"start\"";
         insertButtons(array('label' => 'Start', 'id'=>'start', 'onclick' => "monsetupAction($name_str, $act_str)"));
     }
     echo "</td>";
     echo "   </tr>";
     $ooe++;
     $line++;
     //echo "<tr><td><input type='checkbox' />$name</td><td>$stat</td><td><a onclick='LoadMainPage("main.php")'>$name</a></td></tr>";
 }

?>

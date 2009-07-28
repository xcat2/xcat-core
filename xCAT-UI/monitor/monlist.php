<?php
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}
 require_once "$TOPDIR/lib/security.php";
 require_once "$TOPDIR/lib/functions.php";
 require_once "$TOPDIR/lib/display.php";

#displayMonitorLists() will generate all the monitoring plug-ins,
#the user can select the plug-ins he wants to operate on,
#and press the "Next" button;
 function displayMonitorLists() {
     #The command "monls -a" is used to get the monitoring plug-ins list
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
         echo "<td><input type='radio' name='radio' id='radio_$name' class='r_plugin' /></td>";
         echo "<td id='$line-0'><a class='description' href='#'>$name</a></td>";
         echo "<td id='$line-1'>$stat</td>";
         if(isset($nodemonstatus)) { echo "<td id='$line-2'>Yes</td>";}else {echo "<td id='$line-2'>No</td>";}
         echo "   </tr>";
         $ooe++;
         $line++;
         //echo "<tr><td><input type='checkbox' />$name</td><td>$stat</td><td><a onclick='LoadMainPage("main.php")'>$name</a></td></tr>";
     }
     return 0;
 }
?>
<script type="text/javascript">
$(function(){
    //the code can't run in firefox; that's strange
    $("#dialog").dialog({buttons: {"OK": function() {$(this).dialog("close");}}, autoOpen: false});
    $(".description").click(function(){
        $.get("monitor/plugin_desc.php", {name: $(this).text()}, function(data){
            $("#dialog").html(data);
            $("#dialog").dialog('open');
            return false;
        })
    });
});
</script>
<div class='mapper' align="left">
	<span>
		<a href='#' onclick='loadMainPage("main.php")'>home</a> /
		<a href='#' onclick='loadMainPage("monitor/monlist.php")'>Monitor</a>
	</span>
</div>
<div>
<ul align="left" id="tips">
    <h3>Tips:</h3>
<li>Click the name of each plugin, you can get the plugin's description.</li>
<li>You can also select one plugin, then you can set node/application status monitoring for the selected plugin</li>
</ul>
</div>
<div style="margin-right:30px;width:auto;margin-left:30px;">
    <table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td></td>
            <td>Plug-in Name</td>
            <td>Status</td>
            <td>Node Status Monitoring</td>
        </tr>
    </thead>
    <tbody id="monlist">
    <?php displayMonitorLists();?>
    </tbody>
</table>
    <div id="status_mon" display="none"></div>
</div>
<div id="dialog" title="Plug-in Description"></div>

<div><?php insertButtons(array('label' => 'Next', 'id'=> 'next', 'onclick' => 'loadMainPage("monitor/stat_mon.php")'))?></div>

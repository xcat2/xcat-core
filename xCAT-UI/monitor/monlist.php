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
     foreach($xml->children() as $response) foreach($response->children() as $data) {
         list($name, $stat) = preg_split("/\s+/", $data);
         echo <<<TAB1
            <tr>
                <td><input type='checkbox' /><a href='#' onClick='loadMainPage("monitor/plugin_desc.php?name=$name")'>$name</a></td>
                <td>$stat</td>
                <td></td>
            </tr>
TAB1;
         //echo "<tr><td><input type='checkbox' />$name</td><td>$stat</td><td><a onclick='LoadMainPage("main.php")'>$name</a></td></tr>";
     }
     return 0;
 }
?>
<script type="text/javascript">
    $(function() {
        $("#head").css("background-color", "rgb(141, 189, 216)");
//        var dialogOpts = {
//            hide: true
//        }
//        $("#description").dialog(dialogOpts);
    });
</script>
<div class='mapper'>
	<span>
		<a href='#' onclick='loadMainPage("main.php")'>home</a> /
		<a href='#' onclick='loadMainPage("monitor/monlist.php")'>Plug-ins' List</a>
	</span>
</div>
<div>
<h3>Tips:</h3>
    <p>Please select the available plug-ins, and click the "next" button for next steps;</p>
</div>
<div>
<table align="center">
    <thead id="head">
        <tr>
            <th>Plug-in Name</th>
            <th>Status</th>
            <th>Node Status Monitoring</th>
        </tr>
    </thead>
    <tbody id="monlist" align="left">
    <?php displayMonitorLists();?>
    </tbody>
</table>
</div>
<div id="description"></div>

<?php insertButtons(array('label'=>'NEXT', 'id'=>'next', 'onclick'=>'loadMainPage("main.php")')); ?>



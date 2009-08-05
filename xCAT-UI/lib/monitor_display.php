<?php
/* 
 * All the <html> code related with monitor interface is put here.
 */
function displayMapper_mon($mapper)
{
    //display the Mapper for monitoring interface;
    //the argument $mapper is an array
    //$mapper = {
    //  "home" => "main.php",
    //  "Monitor" => "monitor/monlist.php",
    //};
    echo "<div class='mapper' align='left'>";
    echo "<span>";
    foreach ($mapper as $key => $value) {
        echo "<a href='#' onclick='loadMainPage(\"$value\")'>$key</a>";
        echo "/";
    }
    echo "</span></div>";
}

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
         echo "<td><input type='radio' name='plugins' value='$name' /></td>";
         echo "<td ><a class='description' href='#'>$name</a></td>";
         echo "<td >$stat</td>";
         if(isset($nodemonstatus)) { echo "<td >Enabled</td>";}else {echo "<td >Disabled</td>";}
         echo "   </tr>";
         $ooe++;
         $line++;
         //echo "<tr><td><input type='checkbox' />$name</td><td>$stat</td><td><a onclick='LoadMainPage("main.php")'>$name</a></td></tr>";
     }
     return 0;
 }

function displayTips($tips)
{
    //to tell the user how to operate on the current web page
    //the argument $tips is an array like this:
    //{
    //  "Click the name of each plugin, you can get the plugin's description.",
    //  "You can also select one plugin, then you can set node/application status monitoring for the selected plugin.",
    //}
    echo '<div id="tips"><p><b>Tips:</b></p>';
    foreach ($tips as $tip) {
        echo "<li>$tip</li>";
        echo "\n";
    }
    echo '</div>';
    return 0;
}

function displayDialog($id, $title)
{
    //add one new <div> to display jQuery dialog;
    echo "<div id=$id title=\"$title\"></div>";
    return 0;
}

function displayMonTable()
{
    //create one table to display the monitoring plugins' list
    echo '<div id="monlist_table">';
    echo <<<TOS1
<table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td></td>
            <td>Plug-in Name</td>
            <td>Status</td>
            <td>Node Status Monitoring</td>
        </tr>
    </thead>
TOS1;
    echo '<tbody id="monlist">';
    displayMonitorLists();
    echo "</tbody></table></div>";
    return 0;
}

function display_stat_mon_table($args)
{
    //create one table to disable or enable node/application monitoring
    //the argument $args are one array like this:
    //{ 'xcatmon' => {
    //      'nodestat' => 'Enabled',
    //      'appstat' => 'Disabled',
    //  },
    //};
    //

    echo '<div style="margin-right: 50px; width:auto; margin-left: 50px">';
    foreach($args as $key => $value) {
        $name = $key;

        if($value{'nodestat'} == 'Enabled') {
            $ns_tobe = 'Disable';
        } else {
            $ns_tobe = 'Enable';
        }
        if($value{'appstat'} == 'Enabled') {
            $as_tobe = 'Disable';
        } else {
            $as_tobe = 'Enable';
        }

    }
    echo "<h3>Node/Application Status Monitoring for $name</h3>";
echo <<<TOS2
<table cellspacing="1" class="tabTable" id="tabTable"><tbody>
<tr class="ListLine0">
<td>Node Status Monitoring</td>
<td>
TOS2;
    insertButtons(array('label'=>$ns_tobe, 'id'=>'node_stat', 'onclick'=>"node_stat_control(\"$name\")"));
    echo '</td>';
    echo '</tr>';
    echo '<tr class="ListLine1">';
    echo '<td>Application Status Monitoring</td>';
    echo '<td>';
    insertbuttons(array('label'=>$as_tobe, 'id'=>'app_stat', 'onclick'=>''));
    echo '</td>';
    echo '</tr>';
    echo '</tbody> </table> </div>';
}

function displayStatus()
{
    //tell the user that the current interface is not done yet...
    echo "<div><p>This interface is still under development -use accordingly.</p></div>";
}

function displayOSITree()
{
    //display the node range tree, but only with the nodes with OSI type
    //this follows the function displayNrTree();
    //it doesn't work on firefox!!!
echo <<<EOS3
<script type="text/javascript">
$(init_ositree());
</script>
<div id=ositree></div>
EOS3;
}

function displayAssociation()
{
    echo '<div id="association">';
echo <<<TOS5
<b>Available Condition/Response Associations</b>
<table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td>Condition</td>
            <td>Response</td>
            <td>Node</td>
            <td>State</td>
        </tr>
    </thead>
TOS5;
    //$xml = docmd("webrun", "", array("lscondresp"));
    //if(getXmlErrors($xml,$errors)) {
        //echo "<p class=Error>",implode(' ', $errors), "</p>";
        //exit;
    //}
    //get all the condition&response associations for RMC
echo <<<TOS6
<tbody>
<tr class="ListLine0">
<td>NodeReachability_H</td>
<td>UpdatexCATNodeStatus</td>
<td>hv8plus01.ppd.pok.ibm.com</td>
<td>Not active</td>
</tr>
<tr class="ListLine1">
<td>NodeReachability</td>
<td>UpdatexCATNodeStatus</td>
<td>hv8plus01.ppd.pok.ibm.com</td>
<td>Not active</td>
</tr>
</tbody>
</table>
</div>
TOS6;
    return 0;
}

function displayCond($noderange)
{
    //the user selects one node/noderange from the #ositree div
    echo '<div id="avail_cond">';
    echo '<b>Available Conditions</b>';
    
    echo '</div>';
    return 0;
}

function displayResp()
{
    echo '<div id="avail_resp">';
    echo '<b>Available Response</b>';
    echo '</div>';
    return 0;
}

?>

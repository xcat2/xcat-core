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

function displayTips($tips)
{
    //to tell the user how to operate on the current web page
    //the argument $tips is an array like this:
    //{
    //  "Click the name of each plugin, you can get the plugin's description.",
    //  "You can also select one plugin, then you can set node/application status monitoring for the selected plugin.",
    //}
    echo '<div><ul align="left" id="tips"><h3>Tips:</h3>';
    foreach ($tips as $tip) {
        echo "<li>$tip</li>";
        echo "\n";
    }
    echo '</ul></div>';
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
    echo '<div style="margin-right:30px;width:auto;margin-left:30px;">';
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

function displayStatus()
{
    //tell the user that the current interface is not done yet...
    echo "<div><p>This interface is still under development -use accordingly.</p></div>";
}
?>

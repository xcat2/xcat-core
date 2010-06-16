<?php

function displayTips($tips)
{
    //to tell the user how to operate on the current web page
    //the argument $tips is an array like this:
    //{
    //  "Click the name of each plugin, you can get the plugin's description.",
    //  "You can also select one plugin, then you can set node/application status monitoring for the selected plugin.",
    //}
    echo '<div class="tips">'; 
    echo '<p class="tips_head"><b>Tips:</b>(Click me to display tips)</p>';
    echo '<div class="tips_content">';
    foreach ($tips as $tip) {
        echo "<p>$tip</p>";
        echo "\n";
    }
    echo "</div>";

    echo '<script type="text/javascript">';
    echo '$(handle_tips());';
    echo '</script>';
    echo '</div>';
    return 0;
}

function insertDiv($id)
{
    echo "<div id=$id></div>";
}

function displayMonTable()
{
    //create one table to display the monitoring plugins' list
    echo '<div id="monlist_table">';
    echo <<<TOS1
<table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td><b>Plug-in Name</b></td>
            <td><b>Status</b></td>
            <td><b>Node Status Monitoring</b></td>
            <td><b>Configure</b></td>
            <td><b>Action</b></td>
        </tr>
    </thead>
TOS1;
echo <<<TOS9
<script type="text/javascript">
    hoverOnMonlist();
</script>
TOS9;
    echo '<tbody id="monlist">';
    displayMonitorLists();
    echo "</tbody></table></div>";
    return 0;
}


function displayStatus()
{
    //tell the user that the current interface is not done yet...
    echo "<div id='devstatus'><p>This interface is still under development -use accordingly.</p></div>";
}

function displayOSITree()
{
    //display the node range tree, but only with the nodes with OSI type
    //this follows the function showNrTreeInput();
        echo "<div id=nrtree-input class='ui-corner-all'>";
echo <<<TOS3
<script type="text/javascript">
    $(function() {
        nrtree = new tree_component(); // -Tree begin
        nrtree.init($("#nrtree-input"),{
            rules: { multiple: "Ctrl" },
            ui: { animation: 250 },
            callback : { onchange : printtree },
            data : {
                type : "json",
                async : "true",
                url: "noderangesource.php"
            }
        });  //Tree finish
    });
</script>
TOS3;
    echo "</div>";
}

function displayAssociation()
{
    //TODO: the return message of "webrun lscondresp" is changed
    //and, also, DataTables is used to draw the tabls
    echo '<div id="association" class="ui-cornel-all">';
echo <<<TOS5
    <script type="text/javascript">
        $("#association").dataTable({
            "bLengthChange": false,
            "bFilter": true,
            "bSort": true,
            "iDisplayLength": 50
        });
    </script>
<table>
    <thead>
        <tr>
            <th>Condition</td>
            <th>Response</td>
            <th>Node</td>
            <th>State</td>
            <th>Action</td>
        </tr>
    </thead>
    <tbody>
TOS5;
    $xml = docmd("webrun", "", array("lscondresp"));
    if(getXmlErrors($xml,$errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
    //get all the condition&response associations for RMC
    foreach ($xml->children() as $response) foreach($response->children() as $data) {
        //get the data from xcatd
        $record = split('"',$data);
        echo "<tr>";
echo <<<TOS6
            <td>$record[1]</td>
            <td>$record[3]</td>
            <td>$record[5]</td>
            <td>$record[7]</td>
TOS6;
        //TODO: insert the button here
        echo "<td>";
        if($record[7] == "Active") {
            echo "<button class='fg-button ui-corner-all ui-state-active' onclick='control_RMCAssoc(\"$record[1]\", \"$record[5]\", \"$record[3]\", \"stop\")'>Disable</button>";
        }else {
            echo "<button class='fg-button ui-corner-all ui-state-active' onclick='control_RMCAssoc(\"$record[1]\", \"$record[5]\", \"$record[3]\", \"start\")'>Enable</button>";
        }
        echo "</td>";
        echo "</tr>";
    }
    echo "</tbody></table></div>";
    return 0;
}

function displayCond()
{
    //display all the avaiable conditions to a <table> element
echo <<<COND
<div id="avail_cond" style="display:none">
<table>
    <thead>
        <tr class="colHeaders">
            <th></td>
            <th>Conditions</td>
        </tr>
    </thead>
    <tbody>
COND;
    $xml = docmd("webrun", '', array("lscondition"));
    foreach($xml->children() as $response) foreach($response->children() as $data) {
        /*
         * the data format like this
         * "HFI_not_configured"              "ca4lpar02" "Not monitored"
         * "Drawer_not_configured"           "ca4lpar02" "Not monitored"
         * "AnyNodeFileSystemSpaceUsed_H"    "ca4lpar02" "Not monitored"
         */
        $tmp = split('"', $data);
        //$tmp[1] = condition name
        //$tmp[3] = nodename
        //$tmp[5] = status
echo <<<TOS99
        <tr>
            <td><input type='radio' name='conditions' value='$tmp[1]]' /></td>
            <td>$tmp[1]</td>
        </tr>
TOS99;
    }

    echo "</tbody></table></div>";
    return 0;

}

function displayResp()
{
echo <<<RESP
<div id="avail_resp" style="display:none">
<table>
    <thead>
        <tr class="colHeaders">
            <th></td>
            <th>Response</td>
        </tr>
    </thead>
    <tbody>
RESP;
  $xml=docmd("webrun", '', array("lsresponse"));
  $ooe=0;
  $line=0;
  foreach($xml->children() as $response) foreach($response->children() as $data) {
      $record = split('"', $data);
      echo "<tr>";
echo <<<TOS7
      <td><input type='checkbox' name='responses' value='$record[1]]' /></td>
      <td>$record[1]</td>
TOS7;
      echo "</tr>";
  }
    echo '</tbody></table></div>';
    return 0;
}

function displayCondResp()
{
    echo '<div id="condresp">';
echo <<<JS00
    <script type="text/javascript">
    $(function() {
        $("#nrtree-input").hide();
        $("#showOpt4association").click(function() {
            if($("#avail_cond").css("display") == "none") {
                $("#nrtree-input").show();
                $("#assobuttonsets").show();
                $("#avail_cond").show();
                $("#avail_resp").show();
            }
        });
        $("#addAssociation").click(function() {
            mkCondResp();
        });

        $("#cancelAssociation").click(function() {
            clearEventDisplay();
        });
    });
    </script>
JS00;
    echo "<div style='display:block'>";
    displayAssociation();
    echo "</div>";
    echo "<div id='showOpt4association' style='display:block; border:1px solid lime;' class='ui-state-active'>";
echo <<<TOS00
<span class="ui-icon ui-icon-triangle-1-e" style="position:absolute"></span>
<p class='ui-state-active'>Click here if you want to create new associations...</p>
TOS00;
    echo "</div>";
    echo "<div id=notify_me></div>";
    echo "<div style='display:block'>";
    displayOSITree();
    echo "<div style='border: 1px dotted orange; float:right; width:73%'>";
echo <<<BTN00
    <div id="assobuttonsets" style="display:none">
        <button id="addAssociation" class="fg-button ui-corner-all ui-state-active">Apply</button>
        <button id="cancelAssociation" class="fg-button ui-corner-all ui-state-active">Cancel</button>
    </div>
BTN00;
    echo "<div>";
    displayCond();
    displayResp();
    echo "</div>";
    echo "</div>";
    echo "</div>";
    echo '</div>';
}

function displayRMCRsrc()
{
echo <<<TOS0
<b>Available RMC Resources</b>
<table id="tabTable" class="tabTable" cellspacing="1">
<thead>
    <tr class="colHeaders">
    <td></td>
    <td>Class Name</td>
    </tr>
</thead>
<tbody>
TOS0;
    $xml = docmd("webrun", "", array("lsrsrc"));
    if(getXmlErrors($xml,$errors)) {
        echo "<p class=Error>",implode(' ', $errors), "</p>";
        exit;
    }
    foreach($xml->children() as $response) foreach($response->children() as $data) {
        //get all the class name
        $classes = explode("=", $data);
    }
    $ooe = 0;
    $line = 0;
    foreach($classes as $class) {
        $ooe = $ooe%2;
        echo "<tr class='ListLine$ooe' id='row$line'>";
        echo "<td><input type='radio' name='classGrp' value='$class' onclick='showRMCAttrib()' /> </td>";
        echo "<td>$class</td>";
        echo "</tr>";
        $ooe++;
        $line++;
    }

    echo "</tbody></table>";
    return 0;
}

function displayRMCAttr()
{
    echo "<p>Select the RMC Resource, you will see all its available attributes here.</p>";
}


function RMCEventLogToTable()
{
    $xml = docmd("webrun", "", array("lsevent"));


    //var_dump($xml);
    foreach($xml->children() as $response) foreach($response->children() as $records)
    {
        //$data should be one array to store all the RMC event log.
        echo "<tr>";
        foreach($records->children() as $data) {
            echo "<td>$data</td>";
        }
        echo "</tr>";
    }
}
//displayRMCEventLog() to display the RMC event logs in one table with "tablesorter" class
function displayRMCEvnetLog()
{
echo '<div id=lseventLog>';
echo <<<TOS8
<script type="text/javascript" type"utf-8">
$("#lseventLog table").dataTable({
    "bLengthChange": false,
    "bFilter": false,
    "bSort": true,
    "iDisplayLength": 50
});
</script>
TOS8;
echo <<<TOS9
<table style='width:100%'>
<thead>
    <tr>
        <th>Category</th>
        <th>Description</th>
        <th>Time</th>
</thead>
<tbody>
TOS9;
    RMCEventLogToTable();
    echo "</tbody></table>";
    echo "</div>";

}

function displayRMCMonshowAttr($attr, $nr) {
    //TODO: should add one argument to support the noderange argument
    echo "<div>";
    echo "<table class='tablesorter' cellspacing='1'>";
    echo "<thead>";
    echo "<tr>";
    echo "<td>Time</td>";
    echo "<td>$attr</td>";
    echo "</tr>";
    echo "</thead>";
    echo "<tbody>";

    if($nr == "cluster") {
        //get all the data by the command "monshow"
        $xml = docmd("monshow", "", array("rmcmon", "-t", "60", "-a", "$attr"));
        //the error handling is skipped
    }elseif($nr == "summary") {
        $xml = docmd("monshow", "", array("rmcmon", "-s", "-t", "60", "-a", "$attr"));
    }else {
        $xml = docmd("monshow", "", array("rmcmon", "$nr", "-t", "60", "-a", "$attr"));
    }
    //the formats of the data are different based on $nr
    $index = 0;
    foreach($xml->children() as $response) foreach($response->children() as $data) {
        //handle the data here
        //skip the first 2 lines
        if($index++ < 2) {
            continue;
        }
        //then, parse "date" & "value"
        $arr = preg_split("/\s+/", $data);
        array_pop($arr);
        //print_r($arr);
        $val = array_pop($arr);
        $time = implode(" ", $arr);
        echo "<tr>";
        echo "<td>$time</td>";
        echo "<td>$val</td>";
        echo "</tr>";
    }
    echo "</tbody>";
    echo "</table>";
    echo "</div>";
}

function displayRMCMonshowGraph($value, $nr) {
//display the RMC Performance Data
$place = $nr.$value;
echo <<<TOS11
<script type="text/javascript">
rmc_monshow_draw_by_flot("$place","$value");
</script>
<div id="$place" style="width:100%;height:240px"></div>
TOS11;
}

/*
 * function displayOptionsForPlugin($plugin)
 * *****************************************
 * when the user selects one plugin, the avaiable configuration options will display in <div id='monconfig'> 
 * TODO: for the non-rmcmon plugins, only the option "node/application status monitoring setting" is shown;
 * 
 * the avaiable view options will also display in <div id='monview'>, 
 * TODO: right now, it's only implemented for rmcmon plugin.
 */
function displayOptionsForPlugin($name)
{
    echo "<div id='monconfig'>";
    echo "<p>Available Configurations for  <b>$name</b></p>";

    echo '<table id="tabTable" class="tabTable" cellspacing="1">';
    echo "<tbody>";

    //set up the options for the plugin with the name "$name"
    if($name == "rmcmon") {
        //node status monitor, RMC events, RMC resources
        echo "<tr class='ListLine0' id='row0'>";
        echo "<td>Node/Application Status Monitoring Setting</td>";
        echo "<td>";
        insertButtons(array('label'=>'Configure', 'id'=>'rmc_nodestatmon', 'onclick'=>'loadMainPage("monitor/stat_mon.php?name=rmcmon")'));
        echo "</td>";
        echo "</tr>";

        echo "<tr class='ListLine1' id='row1'>";
        echo "<td>RMC Events Monitoring Setting</td>";
        echo "<td>";
        insertButtons(array('label'=>'Configure', 'id'=>'rmc_event', 'onclick'=>'loadMainPage("monitor/rmc_event_define.php")'));
        echo "</td>";
        echo "</tr>";

        echo "<tr class='ListLine0' id='row2'>";
        echo "<td>RMC Resource Monitoring Setting</td>";
        echo "<td>";
        insertButtons(array('label'=>'Configure', 'id'=>'rmc_resource', 'onclick'=>'loadMainPage("monitor/rmc_resource_define.php")'));
        echo "</td>";
        echo "</tr>";

    } else {
        //there's only "node status monitoring" is enabled
        echo "<tr class='ListLine0' id='row0'>";
        echo "<td>Node/Application Status Monitoring Setting</td>";
        echo "<td>";
        insertButtons(array('label'=>'Configure', 'id'=>$name."_nodestatmon", 'onclick'=>"loadMainPage(\"monitor/stat_mon.php?name=$name\")"));
        echo "</td>";
        echo "</tr>";
    }

    echo "</tbody></table>";

    echo "</div>";

    echo "<div id='monview'>";
    echo "<p>View Options for <b>$name</b></p>";
    //there should be many choices for the user to view the clusters' status
echo <<<TOS1
<table id="view_tab" class="tabTable" cellspacing="1">
<tbody>
TOS1;
    if($name == "rmcmon") {
        #display two rows, one for RMC event, another for RMC Resource Performance monitoring.
        echo "<tr class='ListLine0' id='row0'>";
        echo "<td>RMC Event Logs</td>";
        echo "<td>";
        insertButtons(array('label'=>'View in Text', 'id'=>'rmc_event_text', 'onclick'=>'loadMainPage("monitor/rmc_lsevent.php")'));
        echo "</td>";
        echo "</tr>";
        echo "<tr class='ListLine1' id='row1'>";
        echo "<td>RMC Resource Logs</td>";
        echo "<td>";
        insertButtons(array('label'=>'View By text/graphics', 'id'=>'rmc_resrc_text', 'onclick'=>'loadMainPage("monitor/rmc_monshow.php")'));
        echo "</td>";
        echo "</tr>";
    }
    else {
        echo "<p>There's no view functions for $name.</p>";
    }

    echo "</tbody></table></div>";
}

/*displayMList() will display the list of monitor plugins
 * For the new style monitor list
 */
function displayMList()
{
    $xml = docmd("monls", "", array('-a'));
    if(getXmlErrors($xml, $errors)) {
        echo "<p class=Error>", implode(' ', $errors), "</p>";
        exit;
    }

    foreach($xml->children() as $response) foreach ($response->children() as $data) {
        list($name, $stat, $nodemon) = preg_split("/\s+/", $data);
        //create .pluginstat class for each plugin
        echo "<div class='pluginstat ui-corner-all' id=$name>";
        //TODO: I have to make it beautiful
        createPluginStatElem($name, $stat, $nodemon);
        echo "</div>";
        echo "<span class='ui-icon ui-icon-grip-dotted-horizontal'></span>";
    }

    return 0;
}

function createPluginStatElem($name, $stat, $nodemon)
{
    if($nodemon) {
        echo "<div class='lef'><span class='ui-icon ui-icon-circle-check'></span></div>";
        echo "<div class='mid'>$name<br/>Enabled</div>";
    }else {
        echo "<div class='lef'><span class='ui-icon ui-icon-circle-close'></span></div>";
        echo "<div class='mid ftsz'>$name<br />Disabled</div>";
    }
   echo "<div class='rig'></div>";

}

?>

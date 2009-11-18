<?php

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

$name = $_REQUEST['name'];
$option = $_REQUEST['opt'];
//display the "configure" and "view" options for the desired monitoring plugin

//displayOptionsForPlugin($name);

switch ($option) {
    case "status":
        //return the status of the plugin with "$name" as name
        updatePluginStat($name);
        break;
    case "enable":
    case "disable":
        //enable/disable the plugin
        //show all the node/range in the cluster
        //and also provide one textarea to allow the user to type
        showNRTreeInput();
        showPluginStat($name, $option);
        break;
    case "conf":
        //show all the options for configuration
        showPluginConf($name);
        break;
    case "view":
        //show all the options for view
        showPluginView($name);
        break;
    case "desc":
        //show all the description of the plugin
    default:
        showPluginDesc($name);
        break;
}

function showPluginConf($name)
{
    //TODO
//echo <<<TOS11
//    <div class="ui-state-highlight ui-corner-all">
//        <p>All the options for configuration are here.</p>
//        <p>choose the options to update them</p>
//    </div>
//    <span class="ui-icon ui-icon-grip-dotted-horizontal"></span>
//TOS11;
    echo "<div id=accordion>";
echo <<<TOS10
    <script type="text/javascript">
    $(function() {
        $("#accordion").accordion({autoHeight: false});
    });
    </script>
    <h3><a href='#'>Application Monitor Setting</a></h3>
    <div id="appmonset">
    <div class="ui-state-highlight ui-corner-all">
    <span class='ui-icon ui-icon-alert' />The configuration for application status monitoring
    has not been implemented; We will consider it later!
    </div>
    </div>
    <h3><a href='#'>The monsetting table Setting</a></h3>
    <div id="monsettingtabset">
    <div class="ui-state-highlight ui-corner-all">
    <p>Press the following buttons to enable/disable the settings</p>
    <p>In order to make it effect, turn to the "Enable/Disable" tab for the plugin</p>
    </div>
    </div>
TOS10;
    echo "</div>";
}

function showPluginView($name)
{
    //TODO
}

function updatePluginStat($name)
{
    $xml = docmd("monls", "", array("$name"));
    foreach($xml->children() as $response) foreach($response->children() as $data) {
        $result = preg_split("/\s+/", $data);
        if($result[0] == $name && $result[1] == "not-monitored") {
            echo "Disabled";
        }else {
            echo "Enabled";
        }
    }
}

function showPluginDesc($name)
{
    //TODO: many "return" keys are missed in the response.
    //We have to figure them out
    $xml = docmd("monls"," ", array("$name", "-d"));
    if (getXmlErrors($xml, $errors)) {
        echo "<p class=Error>monls failed: ", implode(' ',$errors), "</p>\n";
        exit;
    }


    $information = "";
    foreach ($xml->children() as $response) foreach ($response->children() as $data) {
        $information .="<p>$data</p>";
    }
    echo $information;
}

/*
 * changePluginStat($name)
 * which is used to enable/disable the selected plugin,
 * and which return whether they're sucessful or not
 */
function showPluginStat($name, $opt)
{
    //display the nrtree here
    //let the user choose node/noderange to enable/disable monitor plugin
    echo "<div id=stat1>";
    echo "<div class='ui-state-highlight ui-corner-all'>";
echo <<<TOS1
   <script type="text/javascript">
       monPluginSetStat();
       $('input').customInput();
   </script>
TOS1;
    if($opt == 'enable') {
        //monadd: xcatmon has special options
        //moncfg <plugin> <nr>
        //"moncfg rmcmon <nr> -r" is necessary for rmcmon
        //monstart
        echo "<p>The $name Plugin is in Disabled status</p>";
        echo "<p>You can Press the Following button to change its status</p>";
        echo "<p>Select the noderange from the right tree</p>";
        echo "<p>OR: you can type the noderange in the following area</p>";
        echo "</div>";

        insertNRTextEntry();
        echo "<p>When you are trying to enable the plugin</p><p>would you like to support node status monitoring?</p>";
        insertRadioBtn();
        insertButtonSet("Enable","Disable", 0);
    }else if($opt == 'disable') {
        //monstop
        //mondecfg
        echo "<p>The $name Plugin is in Enabled status</p>";
        echo "<p>You can Press the Following button to change its status</p>";
        echo "<p>Select the noderange from the right tree</p>";
        echo "<p>OR: you can type the noderange in the following area</p>";
        echo "</div>";
        insertNRTextEntry();
        echo "<p>When you are trying to enable the plugin</p><p>would you like to support node status monitoring?</p>";
        insertRadioBtn();
        insertButtonSet("Enable","Disable", 1);
    }
    echo "</div>";
}

function insertRadioBtn()
{
    //to provide the choose to support "-n"(node status monitoring)
echo <<<TOS21
    <form>
        <fieldset>
        <input type="radio" name="options" id="radio-1" value="yes" />
        <label for="radio-1">support node status monitor</label>
        <input type="radio" name="options" id="radio-2" value="no" />
        <label for="radio-2">Not support node status monitor</label>
        </fieldset>
    </form>
TOS21;
}

function insertNRTextEntry()
{
    echo "<textarea id='custom-nr' class='ui-corner-all' style='width:100%'>";
    echo "</textarea>";
}

function insertButtonSet($state1, $state2, $default)
{
    echo "<span class='ui-icon ui-icon-grip-solid-horizontal'></span>";
    echo "<div class='fg-buttonset fg-buttonset-single'>";
    if($default == 0) {
        echo "<button class='fg-button ui-state-default ui-state-active ui-priority-primary ui-corner-left'>Enable</button>";
        echo "<button class='fg-button ui-state-default ui-corner-right'>Disable</button>";
    }else {
        echo "<button class='fg-button ui-state-default ui-corner-left'>Enable</button>";
        echo "<button class='fg-button ui-state-default ui-state-active ui-priority-primary ui-corner-right'>Disable</button>";
    }
    echo "</div>";
}

function showNRTreeInput()
{
    echo "<div id=nrtree-input class='ui-state-default ui-corner-all'>";
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

?>

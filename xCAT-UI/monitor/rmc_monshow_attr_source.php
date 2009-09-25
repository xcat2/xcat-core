<?php
if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

//$id is the selected noderange to display
$id = $_REQUEST['id'];
$id = preg_replace('/^,/', '', $id);

if($id == "cluster") {
    //handle the condition: with option -s and the noderange is MN
    show_monshow_options($id);
} elseif($id == "summary") {
    //handle the "-s" option
    //TODO: the condition with option -s and the noderange is SN(s) is not considered
    show_monshow_options($id);

} else {
    //check whether the node is "osi" type or not
    //using the command = webrun "lsdef -t node $id -i nodetype"

    $xml = docmd("webrun", "", array("lsdef $id -i nodetype"));
    //no error message will be returned

    foreach($xml->children() as $response) foreach($response->children() as $data) {

    }
    if(false !== strpos($data, "lpar")) {
        //display the options for the "monshow" command
        show_monshow_options($id);
    } else {
        echo "<b>Currently, it only supports one single node. Please select one single node under the LPAR tree.</b>";
    }
}

function show_monshow_options($id)
{
    echo "<b>Choose the attributes to display</b>";
    show_rmc_monsetting();
    echo "<div>";
    //click the "OK" button, "monshow" data for the selected attributes will display
    insertButtons(array('label'=>'Text View', 'id'=>'monshow_text_btn', 'onclick'=>"show_monshow_data(\"text\",\"$id\")"));
    insertButtons(array('label'=>'Graph View', 'id'=>'monshow_graph_btn', 'onclick'=>"show_monshow_data(\"graph\",\"$id\")"));
    echo "</div>";
    echo "</div>";
}

function show_rmc_monsetting()
{
    echo "<div id='mon_keys'>";
    echo "<table class='tabTable' cellspacing='1'>";
    echo <<<TOS1
<thead>
<tr class="colHeaders">
<td>Name</td>
<td>Resources</td>
<td>Attributes</td>
<td>comments</td>
</tr>
</thead>
<tbody>
TOS1;
    $xml = docmd("tabdump", "", array("monsetting"));
    $ooe = 0;
    $line = 0;
    foreach($xml->children() as $response) foreach($response->children() as $data)
    {
        #the var #data is one string like this:
        #"rmcmon","rmetrics_IBM.Host","PctTotalTimeIdle:1",,
        #to use "," as the splitter is wrong.
        #list($name, $key, $value,$comments, $disable) = preg_split('/,/',$data);
        if($data[0] == '#') {
            continue;
        }else {
            #parse the data
            $substr = strstr($data, "\","); #remove the $name, it is "rmcmon" now.
            $substr = substr($substr, 2);

            $index = strpos($substr, ',');
            $key = substr($substr, 1, $index-2);

            if(preg_match('/^rmetrics_/', $key) == 0) {
                continue;
            }

            $substr = substr($substr, $index+2);

            $index = strpos($substr, '"');
            $value = substr($substr, 0, $index);

            $substr = substr($substr, $index+2);
            #the left string contains {$comments,$disable};

            $index = strpos($substr, ',');
            if($index == 0) {
                #it means the $comments is empty
                $comments = '';
            } else {
                $comments = substr($substr, 1, $index -2);
            }
            $substr = substr($substr, $index+1);
            #the left string contains {$disable};
            if(strlen($substr)) {
                #not empty
                $index = strpos($substr, '"', 1);
                $disable = substr($substr, 1, $index-1);
                #the RMC key is disabled, so it's skipped
                continue;
            } else {
                $disable = '';
            }

            #the left lines are the contents of "monsetting"
            $ooe %= 2;
            echo "<tr class='ListLine$ooe' id='row$line'>";
            echo "<td>rmcmon</td>";
            echo "<td>",substr($key, 9),"</td>";
            #parset the var $value, the format looks like this:
            #           RecByteRate,$ecPacketRate:1
            #all the attributes are separated by comma,
            #the integer after ":" is the time interval
            $arr = explode(":",$value);
            $attrs = explode(",", $arr[0]);
//            echo "<td>$arr[0]</td>";
            echo "<td><form>";
            foreach ($attrs as $attr) {
                if($attr) {
                    echo "<input type='checkbox' name='attr_$key' value='$attr' />$attr<br/>";
                }
            }
            echo"</form></td>";
            echo "<td>$comments</td>";
            echo "</tr>";

            $line++;
            $ooe ++;
        }
    }
    echo "</tbody></table>";
}

?>

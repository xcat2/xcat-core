<?php
/* 
 * update the condition&response association
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/js/jsonwrapper.php";

//echo <<<TOS5
//<table>
//    <thead>
//        <tr>
//            <th>Condition</td>
//            <th>Response</td>
//            <th>Node</td>
//            <th>State</td>
//            <th>Action</td>
//        </tr>
//    </thead>
//    <tbody>
//TOS5;
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
            echo "<button class='fg-button ui-corner-all'>Disable</button>";
        }else {
            echo "<button class='fg-button ui-corner-all'>Enable</button>";
        }
        echo "</td>";
        echo "</tr>";
//        $association = explode("=", $data);
//
//        $ooe = 0;
//        $line = 0;
//        foreach($association as $elem) {
//            $ooe = $ooe%2;
//            //the format should be
//            //"NodeReachability"\t"EmailRootOffShift"\t"hv8plus01.ppd.pok.ibm.com"\t"Active"
//            $record = explode("\"", $elem);
//            $cond = $record[1];
//            $resp = $record[3];
//            $node = $record[5];
//            $state = $record[7];
//            echo "<tr class='ListLine$ooe' id='row$line'>";
//            echo "<td>$cond</td>";
//            echo "<td>$resp</td>";
//            echo "<td>$node</td>";
//            echo "<td>$state</td>";
//            echo "<td>";
//            if($state == "Active") {
//                insertButtons(array('label'=>'DeActivate', 'id'=>'deactivate', 'onclick'=>"control_RMCAssoc(\"$cond\", \"$node\", \"$resp\", \"stop\")"));
//            }else if($state == "Not active"){
//                insertButtons(array('label'=>'Activate', 'id'=>'activate', 'onclick'=>"control_RMCAssoc(\"$cond\", \"$node\", \"$resp\", \"start\")"));
//            }
//            echo "</td>";
//            echo "</tr>";
//            $ooe++;
//            $line++;
//        }
    }
//    echo "</tbody></table>";
?>

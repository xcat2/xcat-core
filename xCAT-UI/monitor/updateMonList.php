<?php
/* 
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

if(!isset($TOPDIR)) { $TOPDIR="..";}

require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

echo <<<TOS1
<table id="tabTable" class="tabTable" cellspacing="1">
    <thead>
        <tr class="colHeaders">
            <td></td>
            <td>Plug-in Name</td>
            <td>Status</td>
            <td>Node Status Monitoring</td>
            <td>Action</td>
        </tr>
    </thead>
TOS1;
echo <<<TOS9
<script type="text/javascript">
    showPluginOptions();
    showPluginDescription();
</script>
TOS9;
    echo '<tbody id="monlist">';
    displayMonitorLists();
    echo "</tbody></table>";

?>

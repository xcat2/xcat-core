<?php
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}
 require_once "$TOPDIR/lib/security.php";
 require_once "$TOPDIR/lib/functions.php";
 require_once "$TOPDIR/lib/display.php";
 require_once "$TOPDIR/lib/monitor_display.php";

?>
<script type="text/javascript">
    showPluginOptions();
    showPluginDescription();
</script>
<?php
displayMapper_mon(array('home'=>'main.php', 'monitor'=>'monitor/monlist.php'));

displayTips(array("Click the name of each plugin, you can get the plugin's description.",
        "Select one plugin, choose the options for set up monitoring ",
        "Click the button <b>\"Start\", \"Stop\" or \"Restart\"</b> to setup monitoring plugin"));

displayMonTable();

insertDiv("plugin_desc");

insertDiv("options");
?>
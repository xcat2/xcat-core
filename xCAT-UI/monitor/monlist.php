<?php
if(!isset($TOPDIR)) { $TOPDIR="/opt/xcat/ui";}
 require_once "$TOPDIR/lib/security.php";
 require_once "$TOPDIR/lib/functions.php";
 require_once "$TOPDIR/lib/display.php";
 require_once "$TOPDIR/lib/monitor_display.php";

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
function clickNext()
{
    //get the user's selection, and load the web page named "stat_mon.php";
    var item = $('input[@name=plugins][@checked]').val();
    if(item){
        loadMainPage('monitor/stat_mon.php?name='+item);
    }
}
</script>
<?php
displayMapper_mon(array('home'=>'main.php', 'monitor'=>'monitor/monlist.php'));

displayTips(array("Click the name of each plugin, you can get the plugin's description.",
        "You can also select one plugin, then you can set node/application status monitoring for the selected plugin"));

displayMonTable();

displayDialog("dialog", "Plug-in Description");
insertButtons(array('label' => 'Next', 'id'=> 'next', 'onclick'=>'clickNext()'));
?>

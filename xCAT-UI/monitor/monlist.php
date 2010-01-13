<?php
if(!isset($TOPDIR)) { $TOPDIR="..";}
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

displayMapper(array('home'=>'main.php', 'monitor plugins' =>''));

?>

<script type="text/javascript">
$(function() {
    $(".pluginstat:first").toggleClass("ui-state-active");
    $(".pluginstat").hover(
        function() {
            $(this).addClass("ui-state-hover");
        }, 
        function() {
            $(this).removeClass("ui-state-hover");
        }
    );
    $(".pluginstat").click(function(){
        //TODO: only one plugin is allowedto be in active state
        //There will be always only one div in active status
        if($(this).hasClass('ui-state-active')==false) {
            //find another div in active state, toggle it

            $(".pluginstat.ui-state-active").toggleClass("ui-state-active");
            $(this).toggleClass("ui-state-active");
            //then, update the contents in the "#settings" tab
            var selected = $("#settings").tabs('option','selected');
            var name = $(this).attr('id');
            var options = ["desc","conf","view",["enable","disable"]];
            if(selected != 3) {
                $("#settings").tabs('url',selected,"monitor/options.php?name="+name+"&opt="+options[selected]);
            }else {
                //to handle enable/disable
                var str = $(".ui-state-active .mid").html();
                if(str.match("Enabled")==null) {
                    //the plugin is in "disabled" state, we need to enable it
                    $("#settings").tabs('url',3,"monitor/options.php?name="+name+"&opt="+options[3][0]);
                }else {
                    $("#settings").tabs('url',3,"monitor/options.php?name="+name+"&opt="+options[3][1]);
                }
            }
            $("#settings").tabs('load',selected);
        }
    });

    $("#settings").tabs({selected:-1});
    $("#settings").tabs('option','ajaxOptions',{async:false});
    $("#settings").bind('tabsselect', function(event, ui) {
        var name=$('.ui-state-active').attr('id');
        var options = ["desc","conf","view",["enable","disable"]];
        var i;
        for(i=0; i<options.length-1; i++) {
            $("#settings").tabs("url", i, "monitor/options.php?name="+name+"&opt="+options[i]);
        }
        //to handle enable/disable
        var str = $(".ui-state-active .mid").html();
        if(str.match("Enabled")==null) {
            //the plugin is in "disabled" state, we need to enable it
            $("#settings").tabs('url',3,"monitor/options.php?name="+name+"&opt="+options[3][0]);
        }else {
            $("#settings").tabs('url',3,"monitor/options.php?name="+name+"&opt="+options[3][1]);
        }
    });
});
</script>

<div id="plist" class="ui-corner-all">
<?php displayMList(); ?>
</div>
<div id="settings">
    <ul>
        <li><a href="monitor/options.php">Description</a></li>
        <li><a href="monitor/options.php">Configuration</a></li>
        <li><a href="monitor/options.php">View</a></li>
        <li><a href="monitor/options.php">Enable/Disable</a></li>
    </ul>
</div>
<div id="feedback"></div>

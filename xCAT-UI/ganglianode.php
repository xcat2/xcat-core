<?php
echo <<<EEE
<html>
    <head>
        <title>Node {$_GET['n']} Ganglia Report</title>
        <meta content="600" http-equiv="refresh">
        <meta http-equiv="content-type" content="text/html; charset=UTF-8"/>
        <link href="css/style.css" rel=stylesheet type="text/css">
        <link href="css/jquery.jqplot.css" rel=stylesheet type="text/css">
        <script type="text/javascript" src="js/jquery/jquery.min.js"></script>
        <script type="text/javascript" src="js/jquery/jquery-ui.min.js"></script>
        <script type="text/javascript" src="js/ui.js"></script>
EEE;
?>

<script type="text/javascript">
window.onload=function() {    
    includeJs("js/jquery/jquery.jqplot.min.js");
    includeJs("js/jquery/jqplot.dateAxisRenderer.min.js");
    includeJs("js/jquery/jqplot.dateAxisRenderer.min.js");
    includeJs("js/monitor/gangliamon.js");

    var nodePath = $('#nodepath').val();
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliashow;' + nodePath + ';hour;_summary_',
            msg : ''
        },
        
        success: function(data){
            drawNodesummary(data.rsp[0]);
        }
    });

};

function drawNodesummary(summaryString){
    var nodeName = $('#nodename').val();
    var nodeData = new Object();
    var metricArray = summaryString.split(';');
    var metricName = '';
    var valueArray = '';
    var position = 0;
    var tempLength = 0;
    for (var index = 0; index < metricArray.length; index++){
        position = metricArray[index].indexOf(':');

        metricName = metricArray[index].substr(0, position);
        nodeData[metricName] = new Array();
        valueArray = metricArray[index].substr(position + 1).split(',');
        tempLength = valueArray.length;

        for (var i = 0; i < tempLength; i++){
            nodeData[metricName].push(Number(valueArray[i]));
        }
    }
    
    drawLoadFlot('ganglianodeload', nodeName, nodeData['load_one'], nodeData['cpu_num']);
    drawCpuFlot('ganglianodecpu', nodeName, nodeData['cpu_idle']);
    drawMemFlot('ganglianodemem', nodeName, nodeData['mem_free'], nodeData['mem_total']);
    drawDiskFlot('ganglianodedisk', nodeName, nodeData['disk_free'], nodeData['disk_total']);
    drawNetworkFlot('ganglianodenetwork', nodeName, nodeData['bytes_in'], nodeData['bytes_out']);
}
</script>

<?php
echo <<<EEE
    </head>
    <body>
        <input id="nodename" type="hidden" value="{$_GET['n']}"></input>
        <input id="nodepath" type="hidden" value="{$_GET['p']}"></input>
        <div style="background-color:white;" class="tab">
            <table style="border-style:none;">
                <tr>
                    <td style="padding:0;border-style:none;"><div id="ganglianodeload" class="monitor-sum-div"></div></td>
                    <td style="padding:0;border-style:none;"><div id="ganglianodecpu" class="monitor-sum-div"></div></td>
                    <td style="padding:0;border-style: none;"><div id="ganglianodemem" class="monitor-sum-div"></div></td>
                </tr>
                <tr>
                    <td style="padding:0;border-style:none;"><div id="ganglianodedisk" class="monitor-sum-div"></div></td>
                    <td style="padding:0;border-style:none;"><div id="ganglianodenetwork" class="monitor-sum-div"></div></td>
                    <td style="padding:0;border-style:none;"></td>
                </tr>
            </table>
        </div>
    </body>
</html>
EEE;
?>
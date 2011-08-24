/**
 * Global variables
 */
//save grid summary data, update every one minute
var gridData;

//save nodes path, used for getting detail from rrd file
var nodePath = new Object();

//save nodes current status, 
//unknown-> -2, error->-1, warning->0 ,normal->1   which is used for sorting 
var nodeStatus = new Object();

//update timer
var gangliaTimer;


/**
 * Load Ganglia monitoring tool
 * 
 * @return Nothing
 */
function loadGangliaMon() {
	// Get Ganglia tab
	$('#gangliamon').append(createInfoBar('Checking RPMs.'));
	
	//should get the groups first
	if (!$.cookie('groups')){
	    $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'extnoderange',
                tgt : '/.*',
                args : 'subgroups',
                msg : ''
            },

            success : setGroupsCookies
        });
	}
	// Check whether Ganglia RPMs are installed on the xCAT MN
	$.ajax({
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q rrdtool ganglia-gmetad ganglia-gmond'
		},

		success : checkGangliaRPMs
	});
	return;
}

/**
 * Check whether Ganglia RPMs are installed
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function checkGangliaRPMs(data) {
	var gangliaTab = $('#gangliamon');
	gangliaTab.empty();
	// Get the list of Ganglia RPMs installed
	var status = data.rsp.split(/\n/);
	var gangliaRPMs = [ "rrdtool", "ganglia-gmetad", "ganglia-gmond"];
	var warningMsg = 'Before continuing, please install the following packages: ';
	var missingRPMs = false;
	for ( var i in status) {
		if (status[i].indexOf("not installed") > -1) {
			warningMsg += gangliaRPMs[i] + ' ';
			missingRPMs = true;
		}
	}

	// Append Ganglia PDF
	if (missingRPMs) {
		warningMsg += ". Refer to <a href='http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf'>xCAT2-Monitoring.pdf</a> for more information.";

		var warningBar = createWarnBar(warningMsg);
		warningBar.css('margin-bottom', '10px');
		warningBar.prependTo(gangliaTab);
	} else {
	    gangliaTab.append(createInfoBar('Checking Running status.'));
		// Check if ganglia is running on the xCAT MN
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monls',
				tgt : '',
				args : 'gangliamon',
				msg : ''
			},

			success : checkGangliaRunning
		});
	}
	
	return;
}

/**
 * Check whether Ganglia is running
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function checkGangliaRunning(data){
    var gangliaTab = $('#gangliamon');
    var groupsSelectStr = '';
    var groupsArray = $.cookie('groups').split(',');
    gangliaTab.empty();
    if (data.rsp[0].indexOf("not-monitored") > -1) {
        // Create link to start Ganglia
        var startLnk = $('<a href="#">Click here</a>');
        startLnk.css( {
            'color' : 'blue',
            'text-decoration' : 'none'
        });
        startLnk.click(function() {
            // Turn on Ganglia for all nodes
            monitorNode('', 'on');
        });

        // Create warning bar
        var warningBar = $('<div class="ui-state-error ui-corner-all"></div>');
        var msg = $('<p></p>').css({
    		'display': 'inline-block',
    		'width': '90%'
    	});
        var icon = $('<span class="ui-icon ui-icon-alert"></span>').css({
    		'display': 'inline-block',
    		'margin': '10px 5px'
    	});
        warningBar.append(icon);
        msg.append('Please start Ganglia on xCAT. ');
        msg.append(startLnk);
        msg.append(' to start Ganglia.');
        warningBar.append(msg);
        warningBar.css('margin-bottom', '10px');

        // If there are any warning messages, append this warning after it
        var curWarnings = $('#gangliamon').find('.ui-state-error');
        
        if (curWarnings.length) {
            curWarnings.after(warningBar);
        } else {
            warningBar.prependTo(gangliaTab);
        }
        
        return;
    }

    groupsSelectStr = '<select style="padding:0px;" id="gangliagroup">';
    for (var i in groupsArray){
        groupsSelectStr += '<option value="' + groupsArray[i] + '">' + groupsArray[i] + '</option>';
    }
    groupsSelectStr += '</select>';
    
    //help info
    var helpStr = '<table style="float:right"><tr>' +
                  '<td style="background:#66CD00;width:16px;padding:0px;"> </td><td style="padding:0px;border:0px">Normal</td>' +
                  '<td style="background:#FFD700;width:16px;padding:0px;"> </td><td style="padding:0px;">Heavy Load</td>' +
                  '<td style="background:#FF3030;width:16px;padding:0px;"> </td><td style="padding:0px;">Error</td>' +
                  '<td style="background:#8B8B7A;width:16px;padding:0px;"> </td><td style="padding:0px;">Unknown</td>' +
                  '</tr></table>';
    
    //pass checking
    var showStr = '<div><h3 style="display:inline;">Grid Overview</h3>' +
                  '<sup id="hidesup" style="cursor: pointer;color:blue;float:right">[Hide]</sup></div><hr>' +
                  '<div id="gangliaGridSummary"></div>' +
                  '<div><h3 style="display:inline;">Nodes Current Status</h3>' + helpStr + '</div>' +
                  '<hr>Nodes in Group:' + groupsSelectStr +
                  ' order by: <select id="gangliaorder" style="padding:0px;"><option value="name">Name</option>' +
                  '<option value="asc">Ascending</option><option value="des">Descending</option></select>' +
                  '<div id="gangliaNodes"></div>';
    
    //ganglia help information
    
    gangliaTab.append(showStr);

    //get summary data and draw on the page
    $('#gangliaGridSummary').append('Getting Grid summary Data.<img src="images/loader.gif"></img>');
    sendGridSummaryAjax();
    
    //get nodes current status and draw on the page
    $('#gangliaNodes').append('Getting ' + $('#gangliagroup').val() + ' nodes Status.<img src="images/loader.gif"></img>');
    sendNodeCurrentAjax();
    
    //start the timer to update page per minute.
    gangliaTimer = window.setTimeout('updateGangliaPage()', 60000);
    
    //bind the group select change event
    $('#gangliagroup').bind('change', function(){
        var groupname = $(this).val();
        $('#gangliaNodes').html('Getting ' + groupname + ' nodes Status.<img src="images/loader.gif"></img>');
        sendNodeCurrentAjax();
    });
    
    //bind the order select change event
    $('#gangliaorder').bind('change', function(){
        drawGangliaNodesArea($(this).val());
    });
    
    //bind the hide/show buttion event
    $('#gangliamon #hidesup').bind('click', function(){
        var a = $(this).text();
        if ('[Hide]' == $(this).text()){
            $(this).html('[Show]');
        }
        else{
            $(this).html('[Hide]');
        }
        
        $('#gangliaGridSummary').toggle();
    });
}

/**
 * send ajax request to get grid summary information
 * 
 * @param 
 *        
 * @return Nothing
 */
function sendGridSummaryAjax(){
  //get the summary data
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliashow;_grid_;hour;_summary_',
            msg : ''
        },
        
        success: function(data){
            createGridSummaryData(data.rsp[0]);
            drawGridSummary();
        }
    });
}

/**
 * send ajax request to get nodes current load information
 * 
 * @param which group name want to get
 *        
 * @return Nothing
 */
function sendNodeCurrentAjax(){
    var groupname = $('#gangliagroup').val();
  //get all nodes current status
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliacurrent;node;' + groupname,
            msg : ''
        },
        
        success: function(data){
            createNodeStatusData(data.rsp[0]);
            drawGangliaNodesArea($('#gangliaorder').val());
        }
    });
}

/**
 * send ajax request to get grid current summary information for update the page
 * 
 * @param 
 *        
 * @return Nothing
 */
function sendGridCurrentAjax(){
    //get the summary data
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliacurrent;grid',
            msg : ''
        },
        
        success: function(data){
            updateGridSummaryData(data.rsp[0]);
            drawGridSummary();
        }
    });
}

/**
 * save the grid summary data to local global variable
 * 
 * @param data structure
 *            metric1:time11,val11,time12,val12....;metric2:time21,val21,time22,val22,...;....
 * @return Nothing
 */
function createGridSummaryData(summaryString){
    //empty the global data
    gridData = new Object();
    
    var metricArray = summaryString.split(';');
    var metricname = '';
    var valueArray = '';
    var position = 0;
    var tempLength = 0;
    for (var index = 0; index < metricArray.length; index++){
        position = metricArray[index].indexOf(':');
        //get the metric name and init its global array to save timestamp and value pair
        metricname = metricArray[index].substr(0, position);
        gridData[metricname] = new Array();
        valueArray = metricArray[index].substr(position + 1).split(',');
        tempLength = valueArray.length;
        //save timestamp and value into global array
        for (var i = 0; i < tempLength; i++){
            gridData[metricname].push(Number(valueArray[i]));
        }
    }
}

/**
 * update the grid summary data to local global variable
 * 
 * @param data structure
 *            metric1:time11,val11;metric2:time21,val21,time22;....
 * @return Nothing
 */
function updateGridSummaryData(currentString){
    var metricArray = currentString.split(';');
    var metricname = '';
    var position = 0;
    var tempLength = 0;
    var index = 0;
    var tempArray;
    
    tempLength = metricArray.length;
    for (index = 0; index < tempLength; index++){
        position = metricArray[index].indexOf(':');
        metricname = metricArray[index].substr(0, position);
        tempArray = metricArray[index].substr(position + 1).split(',');
        if (gridData[metricname]){
            gridData[metricname].shift();
            gridData[metricname].shift();
            gridData[metricname].push(Number(tempArray[0]));
            gridData[metricname].push(Number(tempArray[1]));
        }
    }
}
/**
 * draw the Grid summay area by global data
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function drawGridSummary() {
    var gridDrawArea = $('#gangliaGridSummary');
    var showStr = '';
    var tempStr = $('#gangliamon').attr('class');
    
    //jqflot only draw on the area visiable, if the tab is hide, return directly
    if (-1 != tempStr.indexOf('hide')){
        return;
    };
    
    if ('[Show]' == $('#gangliamon #hidesup').text()){
        return;
    }
    gridDrawArea.empty();
    showStr = '<table style="border-style:none;"><tr><td style="padding:0;border-style:none;"><div id="gangliasummaryload" class="monitorsumdiv"></div></td>' + 
              '<td style="padding:0;border-style:none;"><div id="gangliasummarycpu" class="monitorsumdiv"></div></td>' +
              '<td style="padding:0;border-style:none;"><div id="gangliasummarymem" class="monitorsumdiv"></div></td></tr>' +
              '<tr><td style="padding:0;border-style:none;"><div id="gangliasummarydisk" class="monitorsumdiv"></div></td>' +
              '<td style="padding:0;border-style:none;"><div id="gangliasummarynetwork" class="monitorsumdiv"></div></td>' +
              '<td style="padding:0;border-style:none;"></td></tr></table>';
    gridDrawArea.append(showStr);
    drawLoadFlot('gangliasummaryload', 'Grid', gridData['load_one'], gridData['cpu_num']);
    drawCpuFlot('gangliasummarycpu', 'Grid', gridData['cpu_idle']);
    drawMemFlot('gangliasummarymem', 'Grid', gridData['mem_free'], gridData['mem_total']);
    drawDiskFlot('gangliasummarydisk', 'Grid', gridData['disk_free'], gridData['disk_total']);
    drawNetworkFlot('gangliasummarynetwork', 'Grid', gridData['bytes_in'], gridData['bytes_out']);
}

/**
 * draw the load flot by data(maybe summary data, or one node's data)
 * 
 * @param areaid: which div draw this flot
 *        loadpair: the load timestamp and value pair
 *        cpupair: the cpu number and value pair
 *            
 * @return Nothing
 */
function drawLoadFlot(areaid, titleprefix, loadpair, cpupair){
    var load = new Array();
    var cpunum = new Array();
    var index = 0;
    var templength = 0;
    var yaxismax = 0;
    var interval = 1;
    
    $('#' + areaid).empty();
    //parse load pair, the timestamp must mutiply 1000, javascript time stamp is millisecond
    templength = loadpair.length;
    for (index = 0; index < templength; index += 2){
        load.push([loadpair[index] * 1000, loadpair[index + 1]]);
        if (loadpair[index + 1] > yaxismax){
            yaxismax = loadpair[index + 1];
        }
    }
    
    //parse cpu pair
    templength = cpupair.length;
    for (index = 0; index < templength; index += 2){
        cpunum.push([cpupair[index] * 1000, cpupair[index + 1]]);
        if (cpupair[index + 1] > yaxismax){
            yaxismax = cpupair[index + 1];
        }
    }
    
    interval = parseInt(yaxismax / 3);
    if (interval < 1){
        interval = 1;
    }
    $.jqplot(areaid, [load, cpunum],{
        title: titleprefix + ' Loads/Procs Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickInterval : interval
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Load'}, {label: 'CPU Number'}],
        seriesDefaults : {showMarker: false}
    } 
    );
}

/**
 * draw the cpu usage flot by data(maybe summary data, or one node's data)
 * 
 * @param areaid: which div draw this flot
 *        titleprefix : title used name
 *        cpupair: the cpu timestamp and value pair
 *            
 * @return Nothing
 */
function drawCpuFlot(areaid, titleprefix, cpupair){
    var cpu = new Array();
    var index = 0;
    var tempLength = 0;
    
    $('#' + areaid).empty();
    tempLength = cpupair.length;
    // time stamp should mutiply 1000
    // we get the cpu idle from server, we should use 1 subtract the idle.
    for(index = 0; index < tempLength; index +=2){
        cpu.push([(cpupair[index] * 1000), (100 - cpupair[index + 1])]);
    }
    
    $.jqplot(areaid, [cpu],{
        title: titleprefix + ' Cpu Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                max : 100,
                tickOptions:{formatString : '%d\%'}
            }
        },
        seriesDefaults : {showMarker: false}
    } 
    );
}

/**
 * draw the memory usage flot by data(maybe summary data, or one node's data)
 * 
 * @param areaid: which div draw this flot
 *        titleprefix : title used name
 *        cpupair: the cpu timestamp and value pair
 *            
 * @return Nothing
 */
function drawMemFlot(areaid, titleprefix, freepair, totalpair){
    var use = new Array();
    var total = new Array();
    var tempsize = 0;
    var index = 0;
    
    $('#' + areaid).empty();
    if(freepair.length < totalpair.length){
        tempsize = freepair.length;
    }
    else{
        tempsize = freepair.length;
    }
    
    for(index = 0; index < tempsize; index += 2){
        var temptotal = totalpair[index + 1];
        var tempuse = temptotal - freepair[index + 1];
        temptotal = temptotal / 1000000;
        tempuse = tempuse / 1000000;
        total.push([totalpair[index] * 1000, temptotal]);
        use.push([freepair[index] * 1000, tempuse]);
    }
    
    $.jqplot(areaid, [use, total],{
        title: titleprefix + ' Memory Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickOptions:{formatString : '%.2fG'}
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Used'}, {label: 'Total'}],
        seriesDefaults : {showMarker: false}
    } 
    );
}

/**
 * draw the disk usage flot by data(maybe summary data, or one node's data)
 * 
 * @param areaid: which div draw this flot
 *        titleprefix : title used name
 *        freepair: the free disk number, ganglia only log the free data
 *        totalpair: the all disk number
 *            
 * @return Nothing
 */
function drawDiskFlot(areaid, titleprefix, freepair, totalpair){
    var use = new Array();
    var total = new Array();
    var tempsize = 0;
    var index = 0;
    
    $('#' + areaid).empty();
    if(freepair.length < totalpair.length){
        tempsize = freepair.length;
    }
    else{
        tempsize = freepair.length;
    }
    
    for(index = 0; index < tempsize; index += 2){
        var temptotal = totalpair[index + 1];
        var tempuse = temptotal - freepair[index + 1];
        total.push([totalpair[index] * 1000, temptotal]);
        use.push([freepair[index] * 1000, tempuse]);
    }
    
    $.jqplot(areaid, [use, total],{
        title: titleprefix + ' Disk Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickOptions:{formatString : '%.2fG'}
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Used'}, {label: 'Total'}],
        seriesDefaults : {showMarker: false}
    } 
    );
}

function drawNetworkFlot(areaid, titleprefix, inpair, outpair){
    var inArray = new Array();
    var outArray = new Array();
    var templength = 0;
    var index = 0;
    var maxvalue = 0;
    var unitname = 'B';
    var divisor = 1;
    
    templength = inpair.length;
    for (index = 0; index < templength; index += 2){
        if (inpair[index + 1] > maxvalue){
            maxvalue = inpair[index + 1];
        }
    }
    
    templength = outpair.length;
    for (index = 0; index < templength; index += 2){
        if (outpair[index + 1] > maxvalue){
            maxvalue = outpair[index + 1];
        }
    }
    
    if (maxvalue > 3000000){
        divisor = 1000000;
        unitname = 'GB';
    }
    else if(maxvalue >= 3000){
        divisor = 1000;
        unitname = 'MB';
    }
    else{
        //do nothing
    }
    
    templength = inpair.length;
    for (index = 0; index < templength; index += 2){
        inArray.push([(inpair[index] * 1000), (inpair[index + 1] / divisor)]);
    }
    
    templength = outpair.length;
    for (index = 0; index < templength; index += 2){
        outArray.push([(outpair[index] * 1000), (outpair[index + 1] / divisor)]);
    }
    
    $.jqplot(areaid, [inArray, outArray],{
        title: titleprefix + ' Network Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickOptions:{formatString : '%d' + unitname}
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'In'}, {label: 'Out'}],
        seriesDefaults : {showMarker: false}
    } 
    );
}

function createNodeStatusData(nodesStatus){
    var index;
    var nodesArray = nodesStatus.split(';');
    var position = 0;
    var nodename = '';
    var index = 0;
    var tempArray;
    var tempStr = '';
    var templength = nodesArray.length;
    
    for (index in nodePath){
        delete(nodePath[index]);
    }
    
    for (index in nodeStatus){
        delete(nodeStatus[index]);
    }
    
    for (index = 0; index < templength; index++){
        tempStr = nodesArray[index];
        position = tempStr.indexOf(':');
        nodename = tempStr.substring(0, position);
        tempArray = tempStr.substring(position + 1).split(',');
        
        switch(tempArray[0]){
            case 'UNKNOWN':{
                nodeStatus[nodename] = -2;
            }
            break;
            case 'ERROR':{
                nodeStatus[nodename] = -1;
            }
            break;
            case 'WARNING':{
                nodeStatus[nodename] = 0;
                nodePath[nodename] = tempArray[1];
            }
            break;
            case 'NORMAL':{
                nodeStatus[nodename] = 1;
                nodePath[nodename] = tempArray[1];
            }
            break;
        }
    }
}
/**
 * draw nodes current status, there are four type:
 *  a. unknown(gray): can not find save data for this node
 *  b. error(red): get status sometime early, but can not get now
 *  c. warning(orange): node are heavy load
 *  d. normal(green): 
 * 
 * @param 
 *            
 * @return Nothing
 */
function drawGangliaNodesArea(ordertype){
    var index = 0;
    var templength = 0;
    var showStr = '';
    var nodename = '';
    var sortarray = new Array();
    $('#gangliaNodes').html('<ul style="margin:0px;padding:0px;"></ul>');
    //empty the hash
    for (index in nodeStatus){
        sortarray.push([index, nodeStatus[index]]);
    }
    
    if ('asc' == ordertype){
        sortarray.sort(statusAsc);
    }
    else if('des' == ordertype){
        sortarray.sort(statusDes);
    }
    else{
        //do nothing
    }
    
    templength = sortarray.length;
    for (index = 0; index < templength; index++){
        nodename = sortarray[index][0];
        switch(sortarray[index][1]){
            case -2:{
                showStr = '<li class="monitorunknown ui-corner-all monitornodeli" ' + 
                        'title="' + nodename + '"></li>';
            }
            break;
            case -1:{
                showStr = '<li class="monitorerror ui-corner-all monitornodeli" ' + 
                        'title="' + nodename + '"></li>';
            }
            break;
            case 0:{
                showStr = '<li class="mornitorwarning ui-corner-all monitornodeli" ' + 
                        'title="' + nodename + '"></li>';
            }
            break;
            case 1:{
                showStr = '<li class="monitornormal ui-corner-all monitornodeli" ' + 
                        'title="' + nodename + '"></li>';
            }
            break;
        }
        $('#gangliaNodes ul').append(showStr);
    }
    
    //bind all normal and warning nodes' click event
    $('.monitornormal,.monitorwarning').bind('click', function(){
        var nodename = $(this).attr('title');
        window.open('ganglianode.php?n=' + nodename + '&p=' + nodePath[nodename],
                'nodedetail','height=430,width=950,scrollbars=yes,status =no');
    });
    
}

/**
 * update all tab per minute.
 * 
 * @param 
 *            
 * @return Nothing
 */
function updateGangliaPage(){
    if ($('#gangliaNodes').size() < 1){
        return;
    }
    
    sendGridCurrentAjax();
    sendNodeCurrentAjax();
    
    gangliaTimer = window.setTimeout('updateGangliaPage()', 60000);
}

function statusAsc(a, b){
    return a[1] - b[1];
}

function statusDes(a, b){
    return b[1] - a[1];
}
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

//global frame hash
var framehash;
//global cec hash
var cechash;
//global blade hash
var bladehash;
//global x rack hash
var rackhash;
//global other type node hash
var otherhash;
/**
 * Load Ganglia monitoring tool
 * 
 * @return Nothing
 */
function loadGangliaMon() {
	// Get Ganglia tab
	$('#gangliamon').append(createInfoBar('Checking RPMs'));
	
	//should get the groups first
	if (!$.cookie('groups')) {
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
	for (var i in status) {
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
	    gangliaTab.append(createInfoBar('Checking running status'));
		
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
                  '<div><h3 style="display:inline;">Nodes Current Status</h3>' + helpStr + '</div><hr>' +
                  '<div id="zoomDiv" style="padding:0px 0px 12px 0px;"><span name="ALL">All Nodes</span></div>' +
                  '<div id="gangliaNodes"></div>';
    
    //ganglia help information
    
    gangliaTab.append(showStr);

    //get summary data and draw on the page
    $('#gangliaGridSummary').append('Getting grid summary data <img src="images/loader.gif"></img>');
    sendGridSummaryAjax();
    
    //get all nodes location data which can support the zoom monitor
    $('#gangliaNodes').append('Getting all nodes status <img src="images/loader.gif"></img>');
    sendLocationAjax();
    
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
 * Send AJAX request to get all nodes parent and 
 * position to create hardware hierarchy hash  
 * 
 * retrn : nothing
 */
function sendLocationAjax(){
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'graph',
            msg : ''
        },
        
        success: function(data){
        	if(!data.rsp[0]){
				return;
			}
        	extractLocationlData(data.rsp[0]);
        	//get nodes current status and draw on the page
            sendNodeCurrentAjax();
            
            //start the timer to update page per minute.
            gangliaTimer = window.setTimeout('updateGangliaPage()', 60000);
        }
    });
}

/**
 * Send AJAX request to get grid summary information
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
 * Send AJAX request to get nodes current load information
 *        
 * @return Nothing
 */
function sendNodeCurrentAjax(){
    
    //get all nodes current status
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliacurrent;node;',
            msg : ''
        },
        
        success: function(data){
            createNodeStatusData(data.rsp[0]);
            drawGangliaNodesArea($('#gangliaorder').val());
        }
    });
}

/**
 * Send AJAX request to get grid current summary information for update the page
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
 * Save the grid summary data to local global variable
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
 * Update the grid summary data to local global variable
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
    for (index = 0; index < tempLength; index++) {
        position = metricArray[index].indexOf(':');
        metricname = metricArray[index].substr(0, position);
        tempArray = metricArray[index].substr(position + 1).split(',');
        if (gridData[metricname]) {
            gridData[metricname].shift();
            gridData[metricname].shift();
            gridData[metricname].push(Number(tempArray[0]));
            gridData[metricname].push(Number(tempArray[1]));
        }
    }
}
/**
 * Draw the grid summay area by global data
 * 
 * @return Nothing
 */
function drawGridSummary() {
    var gridDrawArea = $('#gangliaGridSummary');
    var showStr = '';
    var tempStr = $('#gangliamon').attr('class');
    
    //jqflot only draw on the area visiable, if the tab is hide, return directly
    if (tempStr.indexOf('hide') != -1){
        return;
    }
    
    if ($('#gangliamon #hidesup').text() == '[Show]'){
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
 * Draw the load flot by data(summary data, or one node's data)
 * 
 * @param areaid
 * 			Which DIV draw this flot
 * @param loadpair
 * 			The load timestamp and value pair
 * @param cpupair
 * 			The CPU number and value pair
 * @return Nothing
 */
function drawLoadFlot(areaid, titleprefix, loadpair, cpupair){
    var load = new Array();
    var cpunum = new Array();
    var index = 0;
    var yaxismax = 0;
    var interval = 1;
    
    $('#' + areaid).empty();
    //parse load pair, the timestamp must mutiply 1000, javascript time stamp is millisecond
    for (index = 0; index < loadpair.length; index += 2){
        load.push([loadpair[index] * 1000, loadpair[index + 1]]);
        if (loadpair[index + 1] > yaxismax){
            yaxismax = loadpair[index + 1];
        }
    }
    
    //parse cpu pair
    for (index = 0; index < cpupair.length; index += 2){
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
 * Draw the CPU usage flot by data(maybe summary data, or one node's data)
 * 
 * @param areaid
 * 			Which DIV draw this flot
 * @param titleprefix
 * 			Title used name
 * @param cpupair
 * 			The CPU timestamp and value pair        
 * @return Nothing
 */
function drawCpuFlot(areaid, titleprefix, cpupair){
    var cpu = new Array();
    var index = 0;
    
    $('#' + areaid).empty();
    
    // time stamp should mutiply 1000
    // we get the CPU idle from server, we should use 1 subtract the idle
    for (index = 0; index < cpupair.length; index +=2) {
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
 * Draw the memory usage flot by data(summary data, or one node's data)
 * 
 * @param areaid
 * 			Which DIV draw this flot
 * @param titleprefix
 * 			Title used name
 * @param cpupair
 * 			The CPU timestamp and value pair
 * @return Nothing
 */
function drawMemFlot(areaid, titleprefix, freepair, totalpair){
    var use = new Array();
    var total = new Array();
    var tempsize = 0;
    var index = 0;
    
    $('#' + areaid).empty();
    if (freepair.length < totalpair.length) {
        tempsize = freepair.length;
    } else {
        tempsize = freepair.length;
    }
    
    for (index = 0; index < tempsize; index += 2) {
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
 * Draw the disk usage flot by data(summary data, or one node's data)
 * 
 * @param areaid
 * 			Which div draw this flot
 * @param titleprefix
 * 			Title used name
 * @param freepair
 * 			The free disk number, Ganglia only logs the free data
 * @param totalpair
 * 			The total disk number
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

/**
 * Draw the network load flot by data(summary data, or one node's data)
 * 
 * @param areaid
 * 			Which div draw this flot
 * @param titleprefix
 * 			Title used name
 * @param inpair
 * 			The timestamp and value pair for download
 * @param outpair
 * 			The timestamp and value pair for upload
 * @return Nothing
 */
function drawNetworkFlot(areaid, titleprefix, inpair, outpair){
    var inArray = new Array();
    var outArray = new Array();
    var index = 0;
    var maxvalue = 0;
    var unitname = 'B';
    var divisor = 1;
    
    for (index = 0; index < inpair.length; index += 2) {
        if (inpair[index + 1] > maxvalue) {
            maxvalue = inpair[index + 1];
        }
    }
    
    for (index = 0; index < outpair.length; index += 2) {
        if (outpair[index + 1] > maxvalue) {
            maxvalue = outpair[index + 1];
        }
    }
    
    if (maxvalue > 3000000) {
        divisor = 1000000;
        unitname = 'GB';
    } else if (maxvalue >= 3000) {
        divisor = 1000;
        unitname = 'MB';
    } else {
        //do nothing
    }
    
    for (index = 0; index < inpair.length; index += 2) {
        inArray.push([(inpair[index] * 1000), (inpair[index + 1] / divisor)]);
    }
    
    for (index = 0; index < outpair.length; index += 2) {
        outArray.push([(outpair[index] * 1000), (outpair[index + 1] / divisor)]);
    }
    
    $.jqplot(areaid, [inArray, outArray], {
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
    });
}

/**
 * Create node status data
 * 
 * @param nodesStatus
 * 			Node status
 * @return Nothing
 */
function createNodeStatusData(nodesStatus){
    var index;
    var nodesArray = nodesStatus.split(';');
    var position = 0;
    var nodename = '';
    var index = 0;
    var tempArray;
    var tempStr = '';
    
    for (index in nodePath) {
        delete(nodePath[index]);
    }
    
    for (index in nodeStatus) {
        delete(nodeStatus[index]);
    }
    
    for (index = 0; index < nodesArray.length; index++) {
        tempStr = nodesArray[index];
        position = tempStr.indexOf(':');
        nodename = tempStr.substring(0, position);
        tempArray = tempStr.substring(position + 1).split(',');
        nodeStatus[nodename] = tempArray[0];
        if (('WARNING' == tempArray[0]) || ('NORMAL' == tempArray[0])){
        	nodePath[nodename] = tempArray[1];
        }
    }
}

/**
 * Draw nodes current status, there are four type:
 *  a. unknown(gray): can not find save data for this node
 *  b. error(red): get status sometime early, but can not get now
 *  c. warning(orange): node are heavy load
 *  d. normal(green): 
 * 
 * @param 
 * @return Nothing
 */
function drawGangliaNodesArea(){
	var position = 0;
	// find out the last child's type and name
	var currentobj = $('#zoomDiv span:last');
	var type = currentobj.attr('name').toLowerCase();
	var name = currentobj.text();
	position = name.indexOf('(');
	if (position > -1){
		name = name.substr(3, position - 3);
	}
	$('#gangliaNodes').empty();
	
	switch (type){
		//these type draw the node current status
		case 'blade':
		case 'cec':
		case 'rack':
		case 'other':
		{
			drawGangliaNodesAreaPic(type, name);
		}
		break;
		//these type draw a summary table
		case 'all':
		case 'frame':
		{
			drawGangliaNodesAreaTab(type, name);
		}
		break;
		default:
			break;
	}
}

function drawGangliaNodesAreaPic(type, name){
	var index = 0;
	var arraypoint;
    var templength = 0;
    var showStr = '';
    var nodename = '';
    
    switch(type){
	    case 'blade':
	    {
	    	arraypoint = bladehash[name];
	    }
	    break;
	    case 'cec':
	    {
	    	arraypoint = cechash[name];
	    }
	    break;
	    case 'rack':
	    {
	    	arraypoint = rackhash[name];
	    }
	    break;
	    case 'other':
	    {
	    	arraypoint = otherhash[1];
	    }
	    default:
	    	break;
    }
    $('#gangliaNodes').html('<ul style="margin:0px;padding:0px;"></ul>');
    
    templength = arraypoint.length;
    
    for (index = 0; index < templength; index++) {
        nodename = arraypoint[index];
        switch (nodeStatus[nodename]) {
            case 'ERROR':
                showStr = '<li class="monitorerror ui-corner-all monitornodeli" title="' + nodename + '"></li>';
                break;
            case 'WARNING':
                showStr = '<li class="mornitorwarning ui-corner-all monitornodeli" title="' + nodename + '"></li>';
                break;
            case 'NORMAL':
                showStr = '<li class="monitornormal ui-corner-all monitornodeli" title="' + nodename + '"></li>';
                break;
            default:
            	showStr = '<li class="monitorunknown ui-corner-all monitornodeli" title="' + nodename + '"></li>';
            	break;
        }
        $('#gangliaNodes ul').append(showStr);
    }
    
    //bind all normal and warning nodes' click event
    $('.monitornormal,.monitorwarning').bind('click', function() {
        var nodename = $(this).attr('title');
        window.open('ganglianode.php?n=' + nodename + '&p=' + nodePath[nodename],
                'nodedetail','height=430,width=950,scrollbars=yes,status =no');
    });
}

function drawGangliaNodesAreaTab(type, name){
	var tabobj = $('<table></table>');
	var rowstr = '';
	var usedcec = new Object();
	tabobj.append('<tr><th>Name</th><th>Type</th><th>Normal</th><th>Heavy Load</th><th>Error</th><th>Unknown</th></tr>');
	if ('all' == type){
		for(var i in framehash){
			var framename = i;
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="frame">' + framename + '</a></td><td>Frame</td>' + 
			         monitorStatAgg('frame', framehash[i]) + '</tr>';
			tabobj.append(rowstr);
			for(var j in framehash[i]){
				usedcec[framehash[i][j]] = 1;
			}
		}
		
		for (var i in cechash){
			if (usedcec[i]){
				continue;
			}
			var cecname = i;
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="cec">' + cecname + '</a></td><td>CEC</td>' + 
	                 monitorStatAgg('cec', cechash[i]) + '</tr>';
			tabobj.append(rowstr);
		}
		
		for (var i in bladehash){
			var bladename = i;
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="blade">' + bladename + '</a></td><td>Blade</td>' + 
	                 monitorStatAgg('blade', bladehash[i]) + '</tr>';
			tabobj.append(rowstr);
		}
		
		for (var i in rackhash){
			var rackname = i;
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="rack">' + rackname + '</a></td><td>Rack</td>' +
				     monitorStatAgg('rack', rackhash[i]) + '</tr>';
			tabobj.append(rowstr);
		}
		
		if (otherhash[1].length > 0)
		{
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="other">Other</a></td><td>Other</td>' +
			         monitorStatAgg('other', otherhash[1]) + '</tr>';
			tabobj.append(rowstr);
		}
	}
	else{
		for (var i in framehash[name]){
			var cecname = framehash[name][i];
			rowstr = '<tr><td><a href="#" onclick="addZoomDiv(this)" name="cec">' + cecname + '</a></td>' +
			         '<td>CEC</td>' + monitorStatAgg('cec', cechash[cecname]) + '</tr>';
			tabobj.append(rowstr);
		}
	}
	
	$('#gangliaNodes').append(tabobj);
}

/**
 * Update all tab per minute.
 * 
 * @return Nothing
 */
function monitorStatAgg(type, inputarray){
	var normalnum = 0;
	var warningnum = 0;
	var errornum = 0;
	var nuknownnum = 0;
	var tempArray;
	var tempname;
	
	switch(type){
		case 'blade':
		case 'cec':
		case 'rack':
		case 'other':
		{
			tempArray = inputarray;
		}
		break;
		case 'frame':
		{
			tempArray = new Array();
			for (var i in inputarray){
				tempname = inputarray[i];
				for (var j in cechash[tempname]){
					tempArray.push(cechash[tempname][j]);
				}
			}
		}
		break;
		default:
			return;
		break;
	}
	
	for (var i in tempArray){
		tempname = tempArray[i];
		switch(nodeStatus[tempname]){
			case 'NORMAL':
				normalnum++;
			break;
			case 'WARNING':
				warningnum++;
			break;
			case 'ERROR':
				errornum++;
			break;
			default:
				nuknownnum++;
			break;
		}
	}
	
	normalnum = normalnum?normalnum:'-';
	warningnum = warningnum?warningnum:'-';
	errornum = errornum?errornum:'-';
	nuknownnum = nuknownnum?nuknownnum:'-';
	
	return ('<td>' + normalnum + '</td><td>' + warningnum + '</td><td>' + errornum + '</td><td>' + nuknownnum + '</td>');
}

/**
 * Update all tab per minute.
 * 
 * @return Nothing
 */
function updateGangliaPage(){
    if ($('#gangliaNodes').size() < 1) {
        return;
    }
    
    sendGridCurrentAjax();
    sendNodeCurrentAjax();
    
    gangliaTimer = window.setTimeout('updateGangliaPage()', 60000);
}

/**
 * extract the location query data, saved in global varible.
 * 
 * @return Nothing
 */
function extractLocationlData(locationData){
	framehash = new Object();
	cechash = new Object();
	bladehash = new Object();
	rackhash = new Object();
	//other unknown nodes only have one parent, use number 1 as there parent
	otherhash = new Object();
	otherhash[1] = new Array();
	
	var allnodearray = locationData.split(';');
	var temparray;
	var parent = '';
	var name = '';
	for(var i in allnodearray){
		temparray = allnodearray[i].split(':');
		name = temparray[0];
		//there is not parent(or mpa, or rack) information, jump this node
		parent = temparray[2];
		if (!parent){
			continue;
		}
		switch(temparray[1].toLowerCase()){
			case 'blade':
			{
				if (!bladehash[parent]){
					bladehash[parent] = new Array();
				}
				
				bladehash[parent].push(name);
			}
			break;
			
			case 'systemx':
			{
				if (!rackhash[parent]){
					rackhash[parent] = new Array();
				}
				rackhash[parent].push(name);
			}
			break;
			
			case 'frame':
			{
				if (!framehash[name])
				{
					framehash[name] = new Array();
				}
			}
			break;

			case 'cec':
			{
				if (!framehash[parent]){
					framehash[parent] = new Array();
				}
				framehash[parent].push(name);
			}
			break;
			
			case 'lpar':
			case 'lpar,osi':
			case 'osi,lpar':
			{
				if (!cechash[parent]){
					cechash[parent] = new Array();
				}
				cechash[parent].push(name);
			}
			break;
			default:
			{
				otherhash[1].push(name);
			}
			break;
		}
	}
}

/**
 * change the zoom area when click the zoom button
 * 
 * @return Nothing
 */
function updateZoom(obj){
	var type=$(obj).attr('name');
	//delete all next cusion
	while($('#zoomDiv span:last').attr('name') != type){
		$('#zoomDiv span:last').remove();
	}
	$(obj).removeClass('monitorzoomlinkli');
	$(obj).unbind('click');
	
	drawGangliaNodesArea();
}

/**
 * add the zoom level when click the group link in the summary table
 * 
 * @return Nothing
 */
function addZoomDiv(obj){
	var name = $(obj).text();
	var type = $(obj).attr('name');
	
	var lastzoomobj = $('#zoomDiv span:last');
	lastzoomobj.addClass('monitorzoomlink');
	lastzoomobj.bind('click', function(){
		updateZoom(this);
	});
	
	var newcontent = ' > ' + name + '(' + type.toUpperCase() + ')';
	var newli = '<span name="' + type + '">' + newcontent + '</span>';
	$('#zoomDiv').append(newli);
	
	drawGangliaNodesArea();
}
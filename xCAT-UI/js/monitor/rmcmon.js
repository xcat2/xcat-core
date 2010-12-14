var globalErrNodes;
var globalNodesDetail;
var globalAllNodesNum = 0;
var globalFinishNodesNum = 0;
var globalSelectedAttributes = '';
var globalTimeStamp;

function loadRmcMon(){
	//find the rmcmon tab
	var rmcMonTab = $('#rmcmon');
	
	//add the stauts bar first. id = 'rmcMonStatus'
	var rmcStatusBar = createStatusBar('rmcMonStatus');
	rmcStatusBar.append(createLoader());
	rmcMonTab.append(rmcStatusBar);
	
	//add the configure button.
	var configButton = createButton('Configure');
	configButton.hide();
	configButton.click(function(){
		if ($('#rmcMonConfig').is(':hidden')){
			$('#rmcMonConfig').show();
		}
		else{
			$('#rmcMonConfig').hide();
		}
	});
	rmcMonTab.append(configButton);
	
	//add configure div
	rmcMonTab.append("<div id='rmcMonConfig'></div>");
	$('#rmcMonConfig').hide();
	
	//load the configure div's content
	loadRmcMonConfigure();
	
	//add the content of the rmcmon, id = 'rmcMonTab'
	rmcMonTab.append("<div id='rmcMonShow'><div id='rmcmonSummary'></div><div id='rmcmonDetail'></div><div id='nodeDetail'></div></div>");
	$('#nodeDetail').hide();
	
	//check the software work status by platform(linux and aix)
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'ostype'
		},

		success : rsctRpmCheck
	});
}

function loadRmcMonConfigure(){
	//get the configure div and clean its content.
	var rmcmonCfgDiv = $('#rmcMonConfig');
	rmcmonCfgDiv.empty();
	
	//add the start button
	var startButton = createButton('Start');
	rmcmonCfgDiv.append(startButton);
	startButton.click(function(){
		$('#rmcMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'rmcstart;lpar',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
			}
		});
	});
	
	//add the stop button
	var stopButton = createButton('Stop');
	rmcmonCfgDiv.append(stopButton);
	stopButton.click(function(){
		$('#rmcMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monstop',
				tgt : '',
				args : 'rmcmon',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
			}
		});
	});
	
	//add the attributes button
	var attrButton = createButton('Attribute Select');
	rmcmonCfgDiv.append(attrButton);
	attrButton.bind('click',function(){
		showConfigureDia();
	});
	//add the cancel button
	var cancelButton = createButton('Cancel');
	rmcmonCfgDiv.append(cancelButton);
	cancelButton.click(function(){
		$('#rmcMonConfig').hide();
	});
}

function rsctRpmCheck(data){
	//linux had to check the rscp first
	if ('aix' != data.rsp){
		$.ajax( {
			url : 'lib/systemcmd.php',
			dataType : 'json',
			data : {
				cmd : 'rpm -q rsct.core'
			},

			success : function(data){
				if (-1 != data.rsp.indexOf("not")){
					$('#rmcMonStatus').empty().append(
					'Please install the <a href="http://www14.software.ibm.com/webapp/set2/sas/f/rsct/rmc/download/home.html" target="install_window">RSCT</a> first.<br/>' +
					'You can find more support from <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
				}
				else{
					xcatrmcRpmCheck();
				}
			}
		});
	}
	else{		
		xcatrmcRpmCheck();
	}
}

function xcatrmcRpmCheck(){
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q xCAT-rmc rrdtool'
		},

		success : function(data){
			var softInstallStatus = data.rsp.split(/\n/);
			var needHelp = false;
			$('#rmcMonStatus').empty();
			//check the xcat-rmc
			if(-1 != softInstallStatus[0].indexOf("not")){
				needHelp = true;
				$('#rmcMonStatus').append(
				'Please install the <a href="http://xcat.sourceforge.net/#download" target="install_window">xCAT-rmc</a> first.<br/>');
			}
			
			//check the rrdtool
			if(-1 != softInstallStatus[1].indexOf("not")){
				needHelp = true;
				$('#rmcMonStatus').append(
					'Please install the <a href="http://oss.oetiker.ch/rrdtool/download.en.html" target="install_window">RRD-tool</a> first.<br/>');
			}
			
			//add help info or load the rmc show
			if (needHelp){
				$('#rmcMonStatus').append(
				'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
			}
			else{
				rmcWorkingCheck();
			}
		}
	});
}

function rmcWorkingCheck(){
	$('#rmcMonStatus').empty().append("Checking RMC working status.");
	$('#rmcMonStatus').append(createLoader());
	$('#rmcmon button:first').show();
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'monls',
			tgt : '',
			args : 'rmcmon',
			msg : ''
		},

		success : function(data){
			if (-1 != data.rsp[0].indexOf("not-monitored")){
				$('#rmcMonStatus').empty().append("Please start the RMC Monitoring first.");
				return;
			}
			loadRmcMonShow();
		}
	});
}

function loadRmcMonShow(){
	$('#rmcMonStatus').empty().append("Getting monitoring Data (This step may take a long time).");
	$('#rmcMonStatus').append(createLoader());
	
	//init the selected Attributes string
	if ($.cookie('rmcmonattr')){
		globalSelectedAttributes = $.cookie('rmcmonattr');
	}
	else{
		globalSelectedAttributes = 'PctTotalTimeIdle,PctTotalTimeWait,PctTotalTimeUser,PctTotalTimeKernel,PctRealMemFree';
	}
	
	//load the rmc status summary
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'rmcshow;summary;' + globalSelectedAttributes,
			msg : ''
		},

		success : function(data){			
			showRmcSummary(data.rsp[0]);
		}
	});
}

function showRmcSummary(returnData){
	var attributes = returnData.split(';');
	var attr;
	var attrName;
	var attrValues;
	var attrDiv;
	var summaryTable = $('<table><tbody></tbody></table>');
	var summaryRow;
	globalTimeStamp = new Array();
	//load each nodes' status
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'rmcshow;lpar;' + globalSelectedAttributes,
			msg : ''
		},
		
		success : function(data){
			parseRmcData(data.rsp);
		}		
	});
	
	//create the timestamp, the flot only use the UTC time, so had to change the value, to show the right time
	var tempDate = new Date();	
	var tempOffset = tempDate.getTimezoneOffset();
	var tempTime = tempDate.getTime() - 3600000 - tempOffset * 60000;
	
	for (var i = 0; i < 60; i++){
		globalTimeStamp.push(tempTime + i * 60000);
	}
	
	//show the summary data
	$('#rmcmonSummary').empty().append('<h3>Overview</h3><hr />');
	$('#rmcmonSummary').append(summaryTable);
	
	for ( attr in attributes){
		var tempTd = $('<td style="border:0px;padding:15px 5px;"></td>');
		var tempArray = [];
		var temp = attributes[attr].indexOf(':');
		attrName = attributes[attr].substr(0, temp);
		attrValues = attributes[attr].substr(temp + 1).split(',');
		for (var i in attrValues){
			tempArray.push([globalTimeStamp[i], attrValues[i]]);
		}

		if (0 == (attr % 3)){
			summaryRow = $('<tr></tr>');
			summaryTable.append(summaryRow);
		}
		summaryRow.append(tempTd);
		attrDiv = $('<div class="monitorsumdiv"></div>');
		tempTd.append(attrDiv);
		$.plot(attrDiv, [tempArray], {xaxis: {mode:"time"}});
		attrDiv.append('<center>' + attrName + '</center>');
		
	}	
}

function parseRmcData(returnData){
	var nodeName;
	var nodeStatus;
	var nodeChat;
	
	//clean all the history data, because all of the follow variables are global
	globalAllNodesNum = returnData.length;
	globalFinishNodesNum = 0;
	globalErrNodes = {};
	globalNodesDetail = {};
	
	for (var i in returnData){
		var temp = returnData[i].indexOf(':');;
		nodeName = returnData[i].substr(0, temp);
		nodeStatus = returnData[i].substr(temp + 1).replace(/(^\s*)|(\s*$)/g, '');
		
		//not active nodes
		if ('OK' != nodeStatus){
			globalErrNodes[nodeName] = nodeStatus;
			globalFinishNodesNum ++;
			if (globalFinishNodesNum == globalAllNodesNum){
				showDetail();
			}
			continue;
		}
		
		//ok
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'rmcshow;' + nodeName + ';' + globalSelectedAttributes,
				msg : nodeName
			},
			
			success : function(data){
				var tempObject = {};
				for (var i in data.rsp){
					var temp = data.rsp[i].indexOf(':');
					var attrName = data.rsp[i].substr(0, temp);
					tempObject[attrName] = data.rsp[i].substr(temp + 1);
				}
				globalNodesDetail[data.msg] = tempObject;
				globalFinishNodesNum++;
				if (globalFinishNodesNum == globalAllNodesNum){
					showDetail();
				}
			}		
		});
	}	
}

function showDetail(){
	var nodeChat;
	var select;
	
	var detailFilter = $('<div id="detailFilter"></div>');
		
	$('#rmcMonStatus').empty().append("RMC Monitoring Show");
	$('#rmcmonDetail').empty().append('<h3>Detail</h3><hr />');
	$('#rmcmonDetail').append(detailFilter);
	
	select = $('<select id="metric"></select>');
	for(var node in globalNodesDetail){
		for(var attr in globalNodesDetail[node]){
			select.append('<option value="' + attr + '">' + attr + '</option>');
		}
		break;
	}
	
	detailFilter.append('<b>Metric:&nbsp;</b>');
	detailFilter.append(select);
	detailFilter.append('&nbsp;&nbsp;&nbsp;&nbsp;');
	
	//sort type
	select = $('<select id="sortType"></select>');
	select.append('<option value="1">ascend</option>');
	select.append('<option value="2">descend</option>');
	select.append('<option value="3">node name</option>');
	
	detailFilter.append('<b>Sort:&nbsp;</b>');
	detailFilter.append(select);
	detailFilter.append('&nbsp;&nbsp;&nbsp;&nbsp;');
	
	var filterButton = createButton('Filter');
	detailFilter.append(filterButton);
	filterButton.bind('click', function(){
		var attr = $('#metric').val();
		var type = $('#sortType').val();
		showAllNodes(attr, type);
	});
	
	filterButton.trigger('click');
}

function showAllNodes(attrName, type){
	$('#rmcmonDetail table').remove();
	var detailTable = $('<table><tbody></tbody></table>');
	//remember how many nodes parsed, used for adding new table row
	var parseNum = 0;
	var detailRow;
	var sortArray = new Array();

	$('#rmcmonDetail').append(detailTable);
	
	for (var nodeName in globalErrNodes){
		var tempTd = $('<td style="border:0px;padding:1px 1px;"></td>');
		if (0 == (parseNum % 4)){
			detailRow = $('<tr></tr>');
			detailTable.append(detailRow);
		}
		detailRow.append(tempTd);
		parseNum ++;
		nodeChat = $('<div class="monitornodediv"></div>');
		
		if ('NA' == globalErrNodes[nodeName]){
			nodeChat.css('background-color', '#f47a55');
			nodeChat.append('<center><h4> Not Active</h4></center>');
		}
		else if ('NI' == globalErrNodes[nodeName]){
			nodeChat.css('background-color', '#ffce7b');
			nodeChat.append('<center><h4>' + nodeName + '\'s RSCT is not installed.</h4></center>');
		}
		else if ('NR' == globalErrNodes[nodeName]){
			nodeChat.css('background-color', '#ffce7b');
			nodeChat.append('<center><h4>' + nodeName + '\'s RSCT is not started.</h4></center>');
		}
		tempTd.append(nodeChat);
		tempTd.append('<center>' + nodeName + '</center>');
	}
	
	filterSort(attrName, type, sortArray);
	for (var sortIndex in sortArray){
		var tempTd = $('<td style="border:0px;padding:1px 1px;"></td>');
		if (0 == (parseNum % 4)){
			detailRow = $('<tr></tr>');
			detailTable.append(detailRow);
		}
		detailRow.append(tempTd);
		parseNum ++;
		nodeChat = $('<div class="monitornodediv"></div>');
		tempTd.append(nodeChat);
		

		var tempData = sortArray[sortIndex]['value'].split(',');
		var tempArray = [];
		for (var i in tempData){
			tempArray.push([globalTimeStamp[i], tempData[i]]);				
		}
		$.plot(nodeChat, [tempArray], {xaxis: {mode:"time", tickSize: [20, "minute"]}});

		tempTd.append('<center>' + sortArray[sortIndex]['name'] + '</center>');
		tempTd.css('cursor', 'pointer');
		tempTd.bind('click', function(){
			showNode($('center', $(this)).html());
		});		
	}
}

function showNode(nodeName){
	var nodeTable = $('<table><tbody></tbody></table>');
	var backButton = createButton('Go back to all nodes');
	var nodeRow;
	var parseNum = 0;
	
	$('#rmcmonDetail').hide();
	$('#nodeDetail').empty().show();
	$('#nodeDetail').append('<h3>' + nodeName +' Detail</h3><hr />');
	$('#nodeDetail').append(backButton);
	backButton.bind('click', function(){
		$('#nodeDetail').hide();
		$('#rmcmonDetail').show();
	});

	
	$('#nodeDetail').append(nodeTable);
	
	for(var attr in globalNodesDetail[nodeName]){
		var tempTd = $('<td style="border:0px;padding:1px 1px;"></td>');
		var attrChat = $('<div class="monitornodediv"></div>');
		if (0 == parseNum % 4){
			nodeRow = $('<tr></tr>');
			nodeTable.append(nodeRow);
		}
		nodeRow.append(tempTd);
		parseNum++;
		
		//data
		tempTd.append(attrChat);
		var tempData = globalNodesDetail[nodeName][attr].split(',');
		var tempArray = [];
		for (var i in tempData){
			tempArray.push([globalTimeStamp[i], tempData[i]]);				
		}
		
		$.plot(attrChat, [tempArray], {xaxis: {mode:"time", tickSize: [20, "minute"]}});
		attrChat.append('<center>' + attr +'</center>');
	}
}

function filterSort(attrName, sortType, retArray){
	var tempObj = {};
	
	for(var node in globalNodesDetail){
		tempObj['name'] = node; 
		tempObj['value'] = globalNodesDetail[node][attrName];
		retArray.push(tempObj);
	}
	
	//by node name
	if(3 == sortType){
		retArray.sort(sortName);
	}
	//desend
	else if(2 == sortType){
		retArray.sort(sortDes);
	}
	//ascend
	else{
		retArray.sort(sortAsc);
	}
	
	return;
}

function sortAsc(x, y){
	if(x['value'] > y['value']){
		return 1;
	}
	else{
		return -1;
	}
}

function sortDes(x, y){
	if(x['value'] > y['value']){
		return -1;
	}
	else{
		return 1;
	}
}

function sortName(x, y){
	if(x['name'] > y['name']){
		return 1;
	}
	else{
		return -1;
	}
}

function showConfigureDia(){
	var diaDiv = $('<div class="tab" title="Monitor Attributes Select"></div>');
	var tempArray = globalSelectedAttributes.split(',');
	var selectedAttrHash = new Object();
	var wholeAttrArray = new Array('PctTotalTimeIdle','PctTotalTimeWait','PctTotalTimeUser','PctTotalTimeKernel','PctRealMemFree');
	
	//init the selectedAttrHash
	for (var i in tempArray){
		selectedAttrHash[tempArray[i]] = 1;
	}
	var attrTable = $('<table id="rmcAttrTable"></table>');
	for (var i in wholeAttrArray){
		var name = wholeAttrArray[i];
		var tempString = '<tr>';
		if(selectedAttrHash[name]){
			tempString += '<td><input type="checkbox" name="' + name + '" checked="checked"></td>';
		}
		else{
			tempString += '<td><input type="checkbox" name="' + name + '"></td>';
		}
		
		tempString += '<td>' + name + '</td></tr>';
		attrTable.append(tempString);		
	}
		
	var selectAllButton = createButton('Select All');
	selectAllButton.bind('click', function(){
		$('#rmcAttrTable input[type=checkbox]').attr('checked', true);
	});
	diaDiv.append(selectAllButton);
	
	var unselectAllButton = createButton('Unselect All');
	unselectAllButton.bind('click', function(){
		$('#rmcAttrTable input[type=checkbox]').attr('checked', false);
	});
	diaDiv.append(unselectAllButton);
	
	diaDiv.append(attrTable);
	
	diaDiv.dialog({
		modal: true,
		width: 400,
		close: function(event, ui){
				$(this).remove();
		},
		buttons: {
			cancel : function(){
			 			$(this).dialog('close');
		 			 },
			ok : function(){
		 			//collect all attibutes' name
		 			var str = '';
		 			$('#rmcAttrTable input:checked').each(function(){
		 				if('' == str){
		 					str += $(this).attr('name');
		 				}
		 				else{
		 					str += ',' + $(this).attr('name');
		 				}
		 			});
		 			
		 			//if no attribute is selected, alert the information.
		 			if ('' == str){
		 				alert('Please select one attribute at lease!');
		 				return;
		 			}
		 			
		 			//new selected attributes is different from the old, update the cookie and reload this tab
		 			if ($.cookie('rmcmonattr') != str){
		 				$.cookie('rmcmonattr', str, {path : '/xcat', expires : 10});
		 				//todo reload the tab
		 				$('#rmcmon').empty();
		 				loadRmcMon();
		 			}
			     	$(this).dialog('close');
				 }
		}
	});
}
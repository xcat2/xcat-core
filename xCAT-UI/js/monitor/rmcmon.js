var globalErrNodes;
var globalNodesDetail;
var globalAllNodesNum = 0;
var globalFinishNodesNum = 0;
var globalSelectedAttributes = '';
var globalTimeStamp;
var globalCondition = '';
var globalResponse = new Object();

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

/*===========RMC Event Tab============*/
/**
 * load the rmc event tab.
 * 
 * @param 

 * @return
 *        
 */
function loadRmcEvent(){
	//find the rmcevent tab
	
	//add the stauts bar first. id = 'rmcMonStatus'
	var rmcStatusBar = createStatusBar('rmcEventStatus');
	rmcStatusBar.append(createLoader());
	$('#rmcevent').append(rmcStatusBar);
	$('#rmcevent').append('<div id="rmcEventDiv"></div>');
	
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'lsevent;-O;1000',
			msg : ''
		},

		success : showEventLog
	});
}

/**
 * get all conditions  
 * 
 * 
 * @return
 *        
 */
function getConditions(){
	if ('' == globalCondition){
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'lscondition',
				msg : ''
			},
			
			success : function(data){
				globalCondition = data.rsp[0];
			}
		});
	}
}

/**
 * get all response  
 * 
 * 
 * @return
 *        
 */
function getResponse(){
	var tempFlag = false;
	//get all response first
	for (var i in globalResponse){
		tempFlag = true; 
		break;
	}
	if (!tempFlag){
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'lsresponse',
				msg : ''
			},
			
			success : function(data){
				var resps = data.rsp[0].split(';');
				for(var i in resps){
					var name = resps[i];
					name = name.substr(1, (name.length - 2));
					globalResponse[name] = 1;
				}
			}
		});
	}
}

/**
 * show all the event in the rmc event tab 
 * 
 * @param data response from the xcat server.

 * @return
 *        
 */
function showEventLog(data){
	$('#rmcEventStatus').empty();
	//rsct not installed.
	if (data.rsp[0] && (-1 != data.rsp[0].indexOf('lsevent'))){
		$('#rmcEventStatus').append('Please install RSCT first!');
		return;
	}
	var eventDiv = $('#rmcEventDiv');
	eventDiv.empty();
	
	//add the configure button
	loadRmcEventConfig();
	
	//get conditions and responses, save in the global
	getConditions();
	getResponse();
	
	var eventTable = new DataTable('lsEventTable');
	eventTable.init(['Time', 'Type', 'Content']);
	
	for(var i in data.rsp){
		var row = data.rsp[i].split(';');
		eventTable.add(row);
	}
	
	eventDiv.append(eventTable.object());
	$('#lsEventTable').dataTable({
		'bFilter' : true,
		'bLengthChange' :true,
		'bSort' :true,
		'bPaginate' :true,
		'iDisplayLength' :10
	});
	
	//unsort on the content column
	$('#lsEventTable thead tr th').eq(2).unbind('click');
}

/**
 * Add the configure button into rmc event tab
 * 
 * @param 

 * @return
 *        
 */
function loadRmcEventConfig(){
	var chCondScopeBut = createButton('Change Condition Scope');
	chCondScopeBut.bind('click', function(){
		chCondScopeDia();
	});
	$('#rmcEventDiv').append(chCondScopeBut);
	
	var mkCondRespBut = createButton('Make/Remove Association');
	mkCondRespBut.bind('click', function(){
		mkCondRespDia();
	});
	$('#rmcEventDiv').append(mkCondRespBut);
	
	var startCondRespBut = createButton('Start Association');
	startCondRespBut.bind('click', function(){
		startCondRespDia();
	});
	$('#rmcEventDiv').append(startCondRespBut);
	
	var stopCondRespBut = createButton('Stop Association');
	stopCondRespBut.bind('click', function(){
		stopCondRespDia();
	});
	$('#rmcEventDiv').append(stopCondRespBut);
}

/**
 * show the make association dialogue
 * 
 * @param 

 * @return
 *        
 */
function mkCondRespDia(){
	var diaDiv = $('<div title="Configure Association" id="mkAssociation"><div>');
	
	//2 fieldset conditions, response
	diaDiv.append('<fieldset id="mkAssCond"><legend>Predefined Condition</legend></fieldset>');
	diaDiv.append('<fieldset id="mkAssResp"><legend>Response</legend>Plase select condition first.</fieldset>');
	diaDiv.append('<div id="selectedResp" style="display: none;" ><div>');
	
	//add the conditions into fieldset
	if ('' == globalCondition){
		diaDiv.find('#mkAssCond').append('Getting predefined conditions, open this dislogue later.');
	}
	else{
		diaDiv.find('#mkAssCond').append(createConditionTable(globalCondition));
	}
	
	//change the response field when click the condition
	diaDiv.find('input:radio').bind('click', function(){
		diaDiv.find('#mkAssResp').empty().append('<legend>Response</legend>Getting response').append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'lscondresp;"' + $(this).attr('value') + '"',
				msg : ''
			},
			
			success : function(data){
				var tempHash = new Object();
				var oldSelectedResp = '';
				var showStr = '';
				if (data.rsp[0]){
					var names = data.rsp[0].split(';');
					for (var i in names){
						var name = names[i];
						name = name.substr(1, name.length - 2);
						tempHash[name] = 1;
					}
				}
				
				for(var name in globalResponse){
					if(tempHash[name]){
						showStr += '<input type="checkbox" checked="checked" value="' + name + '">' + name;
						oldSelectedResp += ';' + name;
					}
					else{
						showStr += '<input type="checkbox" value="' + name + '">' + name;
					}
				}
				
				diaDiv.find('#mkAssResp').empty().append('<legend>Response</legend>').append(showStr);
				diaDiv.find('#selectedResp').empty().append(oldSelectedResp);
			}
		});
	});
	
	diaDiv.dialog({
		 modal: true,
         width: 570,
         close: function(event, ui){
					$(this).remove();
				},
		buttons: {
			cancel : function(){
				$(this).dialog('close');
			},
			ok : function(){
				var newResp = new Object();
				var oldResp = new Object();
				var oldString = '';
				var newString = '';
				//get the old seelected responses
				var conditionName = $(this).find('#mkAssCond :checked').attr('value');
				if (!conditionName){
					return;
				}
				var temp = $(this).find('#selectedResp').html();
				if('' == temp){
					return;
				}
				var tempArray = temp.substr(1).split(';');
				for (var i in tempArray){
					oldResp[tempArray[i]] = 1;
				}
				//get the new selected responses
				$(this).find('#mkAssResp input:checked').each(function(){
					var respName = $(this).attr('value');
					newResp[respName] = 1;
				});
				
				for (var i in newResp){
					if(oldResp[i]){
						delete oldResp[i];
						delete newResp[i];
					}
				}
				
				//add the response which are delete.
				for (var i in oldResp){
					oldString += ',"' + i + '"';
				}
				if('' != oldString){
					oldString = oldString.substr(1);
				}
				
				//add the response which are new add
				for (var i in newResp){
					newString += ',"' + i +'"';
				}
				if ('' != newString){
					newString = newString.substr(1);
				}
				
				if(('' != oldString) || ('' != newString)){
					$('#rmcEventStatus').empty().append('Create/Remove associations').append(createLoader());
					$.ajax({
						url : 'lib/cmd.php',
						dataType : 'json',
						data : {
							cmd : 'webrun',
							tgt : '',
							args : 'mkcondresp;"' + conditionName + '";+' + newString + ':-' + oldString,
							msg : ''
						},
						
						success : function(data){
							$('#rmcEventStatus').empty().append(data.rsp[0]);;
						}
					});
				}
				$(this).dialog('close');
			}
		}
	});
}

/**
 * show the remove association dialogue
 * 
 * @param 

 * @return
 *        
 */
function rmCondRespDia(){
	
}

/**
 * show the make condition dialogue
 * 
 * @param 

 * @return
 *        
 */
function chCondScopeDia(){
	var diaDiv = $('<div title="Change Condition Scope" id="chScopeDiaDiv"><div>');
	//3 fieldset to show conditions, group and status
	diaDiv.append('<fieldset id="changePreCond"><legend>Predefined Condition</legend></fieldset>');
	diaDiv.append('<fieldset id="changeGroup"><legend>Group</legend></fieldset>');
	diaDiv.append('<fieldset id="changeStatus"></fieldset>');
	
	//add the groups into fieldset
	var groups = $.cookie('groups').split(',');
	for (var i in groups){
		var tempStr = '<input type="checkbox" value="' + groups[i] + '">' + groups[i];
		diaDiv.find('#changeGroup').append(tempStr);
	}
	
	//add the conditions into fieldset
	if ('' == globalCondition){
		diaDiv.find('#changePreCond').append('Getting predefined conditions, open this dislogue later.');
	}
	else{
		diaDiv.find('#changePreCond').append(createConditionTable(globalCondition));
	}
	
	//create the dislogue
	diaDiv.dialog({
		 modal: true,
        width: 570,
        close: function(event, ui){
					$(this).remove();
				},
		buttons: {
			cancel : function(){
				$(this).dialog('close');
			},
			ok : function(){
				$('#changeStatus').empty().append('<legend>Status</legend>');
				var conditionName = $('#changePreCond :checked').attr('value');
				var groupName = '';
				$('#changeGroup :checked').each(function(){
					if ('' == groupName){
						groupName += $(this).attr('value');
					}
					else{
						groupName += ',' + $(this).attr('value');
					}
				});
				
				if (undefined == conditionName){
					$('#changeStatus').append('Please select conditon.');
					return;
				}
				
				if ('' == groupName){
					$('#changeStatus').append('Please select group.');
					return;
				}
				
				$('#changeStatus').append(createLoader());
				$.ajax({
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'webrun',
						tgt : '',
						args : 'mkcondition;change;' + conditionName + ';' + groupName,
						msg : ''
					},
					
					success : function(data){
						$('#changeStatus img').remove();
						if (-1 != data.rsp[0].indexOf('Error')){
							$('#changeStatus').append(data.rsp[0]);
						}
						else{
							$('#rmcEventStatus').empty().append(data.rsp[0]);
							$('#chScopeDiaDiv').remove();
						}
					}
				});
			}
		}
	});
}

/**
 * show the make response dialogue
 * 
 * @param 

 * @return
 *        
 */
function mkResponseDia(){
	var diaDiv = $('<div title="Make Response"><div>');
	diaDiv.append('under construction.');
	
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
				$(this).dialog('close');
			}
		}
	});
}



/**
 * start the condition and response associations
 * 
 * @param 

 * @return
 *        
 */
function startCondRespDia(){
	var diaDiv = $('<div title="Start Association" id="startAss"><div>');
	diaDiv.append('Getting conditions').append(createLoader());
	
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'lscondition;-n',
			msg : ''
		},
		
		success : function(data){
			if (data.rsp[0]){
				$('#startAss').empty().append(createConditionTable(data.rsp[0]));
				$('#startAss').dialog("option", "position", 'center');
			}
			else{
				$('#startAss').empty().append('There is not non-monitored condition.');
			}
		}
	});
	
	diaDiv.dialog({
		 modal: true,
         width: 570,
         close: function(event, ui){
					$(this).remove();
				},
		buttons: {
			cancel : function(){
				$(this).dialog('close');
			},
			start : function(){
				var conditionName = $('#startAss :checked').attr('value');
				if (!conditionName){
					alert('Select condition name please.');
					return;
				}
				$('#rmcEventStatus').empty().append('Starting monitor on ' + conditionName).append(createLoader());
				$.ajax({
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'webrun',
						tgt : '',
						args : 'startcondresp;' + conditionName,
						msg : ''
					},
					
					success : function(data){
						$('#rmcEventStatus').empty().append(data.rsp[0]);
					}
				});
				$(this).dialog('close');
			}
		}
	});
}

/**
 * stop the condition and response associations
 * 
 * @param 

 * @return
 *        
 */
function stopCondRespDia(){
	var diaDiv = $('<div title="Stop Association" id="stopAss"><div>');
	diaDiv.append('Getting conditions').append(createLoader());
	
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'lscondition;-m',
			msg : ''
		},
		
		success : function(data){
			if (data.rsp[0]){
				$('#stopAss').empty().append(createConditionTable(data.rsp[0]));
				$('#stopAss').dialog("option", "position", 'center');
			}
			else{
				$('#stopAss').empty().append('There is not monitored condition.');
			}
		}
	});
	
	diaDiv.dialog({
		 modal: true,
         width: 570,
         close: function(event, ui){
					$(this).remove();
				},
		buttons: {
			cancel : function(){
				$(this).dialog('close');
			},
			stop : function(){
				var conditionName = $('#stopAss :checked').attr('value');
				if (!conditionName){
					alert('Select condition name please.');
					return;
				}
				$('#rmcEventStatus').empty().append('Stoping monitor on ' + conditionName).append(createLoader());
				$.ajax({
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'webrun',
						tgt : '',
						args : 'stopcondresp;' + conditionName,
						msg : ''
					},
					
					success : function(data){
						$('#rmcEventStatus').empty().append(data.rsp[0]);
					}
				});
				$(this).dialog('close');
			}
		}
	});
}

/**
 * create the condition table for dialogue
 * 
 * @param 

 * @return
 *        
 */
function createConditionTable(cond){
	var conditions = cond.split(';');
	var name = '';
	var showStr = '<table style="font:12px verdana,arial,helvetica,sans-serif;"><tbody>';
	for (var i in conditions){
		name = conditions[i];
		name = name.substr(1, name.length - 2);
		if (0 == i % 2){
			showStr += '<tr><td><input type="radio" name="preCond" value="'+ name + '">' + name + '</td><td width=10></td>' ;
		}
		else{
			showStr += '<td><input type="radio" name="preCond" value="'+ name + '">' + name + '</td></tr>';
		}
	}
	showStr += '</tbody></table>';
	
	return showStr;
}
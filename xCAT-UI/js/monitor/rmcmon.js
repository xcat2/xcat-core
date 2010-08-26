var globalErrNodes;
var globalNodesDetail;
var globalAllNodesNum = 0;
var globalFinishNodesNum = 0;

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
	rmcMonTab.append("<div id='rmcMonShow'><div id='rmcmonSummary'></div><div id='rmcmonDetail'></div></div>");
	
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
					'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
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
	$('#rmcMonStatus').empty().append("Getting monitoring Data.");
	$('#rmcMonStatus').append(createLoader());
	
	//load the rmc status summary
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'rmcshow;summary',
			msg : ''
		},

		success : function(data){			
			showRmcSummary(data.rsp[0]);
		}
	});
	
	//load each nodes' status
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'rmcshow;lpar',
			msg : ''
		},
		
		success : function(data){
			parseRmcData(data.rsp);
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
	

	$('#rmcmonSummary').empty().append('<h3>Overview</h3><hr />');
	$('#rmcmonSummary').append(summaryTable);
	
	for ( attr in attributes){
		var tempTd = $('<td style="border:0px;padding:15px 5px;"></td>');
		var tempArray = [];
		var temp = attributes[attr].indexOf(':');
		attrName = attributes[attr].substr(0, temp);
		attrValues = attributes[attr].substr(temp + 1).split(',');
		for (var i in attrValues){
			tempArray.push([i, attrValues[i]]);
		}

		if (0 == (attr % 3)){
			summaryRow = $('<tr></tr>');
			summaryTable.append(summaryRow);
		}
		summaryRow.append(tempTd);
		attrDiv = $('<div class="monitorsumdiv"></div>');
		tempTd.append(attrDiv);
		$.plot(attrDiv, [tempArray]);
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
				showNodeDetail();
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
				args : 'rmcshow;' + nodeName,
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
					showNodeDetail();
				}
			}		
		});
	}	
}

function showNodeDetail(){
	var nodeChat;
	//remember how many nodes parsed, used for adding new table row
	var parseNum = 0;
	var detailTable = $('<table><tbody></tbody></table>');
	var detailRow;
	
	$('#rmcMonStatus').empty().append("RMC Monitoring Show");
	$('#rmcmonDetail').empty().append('<h3>Detail</h3><hr />');
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
	
	for (var nodeName in globalNodesDetail){
		var tempTd = $('<td style="border:0px;padding:1px 1px;"></td>');
		if (0 == (parseNum % 4)){
			detailRow = $('<tr></tr>');
			detailTable.append(detailRow);
		}
		detailRow.append(tempTd);
		parseNum ++;
		nodeChat = $('<div class="monitornodediv"></div>');
		tempTd.append(nodeChat);
		
		for (var attrName in globalNodesDetail[nodeName]){
			var tempData = globalNodesDetail[nodeName][attrName].split(',');
			var tempArray = [];
			for (var i in tempData){
				tempArray.push([i, tempData[i]]);				
			}
			$.plot(nodeChat, [tempArray]);
			break;
		}
		tempTd.append('<center>' + nodeName + '</center>');
	}
}
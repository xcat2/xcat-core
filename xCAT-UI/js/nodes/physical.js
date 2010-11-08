

var bpaList;
var fspList;
var lparList;
var nodeList;
var selectLpar = new Object();
/**
 * extract all nodes userful data into a hash, which is used for creating graphical
 * 
 * @param data: the response from xcat command "nodels all nodetype.nodetype ppc.parent ..." 
 *
 * @return
 */
function extractGraphicalData(data){
	var nodes = data.rsp;
	nodeList = new Object();
	
	//extract useful info into tempList
	for (var i = 0; i < nodes.length; i++){
		var nodeName = nodes[i][0];
		if (undefined == nodeList[nodeName]){
			nodeList[nodeName] = new Object();
		}
		
		switch(nodes[i][2]){
			case 'nodetype.nodetype': {
				nodeList[nodeName]['type'] = nodes[i][1];
			}
			break;
			case 'ppc.parent' : {
				nodeList[nodeName]['parent'] = nodes[i][1];
			}
			break;
			case 'nodelist.status': {
				nodeList[nodeName]['status'] = nodes[i][1];
			}
			break;
			case 'vpd.mtm': {
				nodeList[nodeName]['mtm'] = nodes[i][1];
			}
			default :
				break;
		}
	}	
}

function createPhysicalLayout(data){
	bpaList = new Object();
	fspList = new Object();
	lparList = new Object();
	
	$('#graphTab').empty();
	for (var temp in data.rsp){
		var nodeName = data.rsp[temp];
		nodeName = nodeName.substring(0, nodeName.indexOf(' '));
		if ('' == nodeName){
			continue;
		}
		fillList(nodeName);
	}
	createGraphical(bpaList, fspList, $('#graphTab'));
}

function fillList(nodeName){
	var parentName = nodeList[nodeName]['parent'];
	var mtm = nodeList[nodeName]['mtm'];
	var status = nodeList[nodeName]['status']; 
	
	switch(nodeList[nodeName]['type']){
		case 'bpa': {
			if (undefined == bpaList[nodeName]){
				bpaList[nodeName] = new Array();
			}
		}
		break;
		case 'lpar,osi': {
			if ('' == parentName){
				break;
			}
			
			if (undefined == fspList[parentName]){
				fillList(parentName);
			}
			
			fspList[parentName]['children'].push(nodeName);
			lparList[nodeName] = status;
		}
		break;
		case 'fsp': {
			if (undefined != fspList[nodeName]){
				break;
			}
			
			fspList[nodeName] = new Array();
			fspList[nodeName]['children'] = new Array();
			fspList[nodeName]['mtm'] = mtm;
			
			if ('' == parentName){
				break;
			}
			
			if (undefined == bpaList[parentName]){
				fillList(parentName);
			}
			
			bpaList[parentName].push(nodeName);
		}
		break;
		default:
			break;
	}
}
/**
 * create the physical graphical layout 
 * 
 * @param bpa : all bpa and there related  fsps
 *        fsp : all fsp and there related lpars
 *        fspinfo : all fsps' hardwareinfo
 *        area: the element to append graphical layout
 * @return
 */
function createGraphical(bpa, fsp, area){
	var usedFsp = new Object();
	var graphTable = $('<table id="graphTable" style="border-color: transparent;"><tbody></tbody></table>');
	var elementNum = 0;
	var row;
	for (var bpaName in bpa){
		if (0 == elementNum % 3){
			row = $('<tr></tr>');
			graphTable.append(row);
		}
		elementNum ++;
		var td = $('<td style="padding:0;border-color: transparent;"></td>');
		var frameDiv = $('<div class="frameDiv"></div>');
		frameDiv.append('<div style="height:27px;">' + bpaName + '</div>');
		for (var fspIndex in bpa[bpaName]){
			var fspName = bpa[bpaName][fspIndex];
			usedFsp[fspName] = 1;
			
			frameDiv.append(createFspDiv(fspName, fsp[fspName]['mtm'], fsp));
			frameDiv.append(createFspTip(fspName, fsp[fspName]['mtm'], fsp));
		}
		td.append(frameDiv);
		row.append(td);
	}
	
	//find the single fsp and sort descend by units 
	var singleFsp = new Array();
	for (var fspName in fsp){
		if (usedFsp[fspName])
		{
			continue;
		}
		
		singleFsp.push([fspName, fsp[fspName]['mtm']]);
	}
	
	singleFsp.sort(function(a, b){
		var unitNumA = 4;
		var unitNumB = 4;
		if (hardwareInfo[a[1]]){
			unitNumA = hardwareInfo[a[1]][1];
		}
		
		if (hardwareInfo[b[1]]){
			unitNumB = hardwareInfo[b[1]][1];
		}
		
		return (unitNumB - unitNumA);
	});
	
	elementNum = 0;
	for (var fspIndex in singleFsp){
		var fspName = singleFsp[fspIndex][0];
		if (0 == elementNum % 3){
			row = $('<tr></tr>');
			graphTable.append(row);
		}
		elementNum ++;

		var td = $('<td style="vertical-align:top;border-color: transparent;"></td>');
		td.append(createFspDiv(fspName, fsp[fspName]['mtm'], fsp));
		td.append(createFspTip(fspName, fsp[fspName]['mtm'], fsp));
		row.append(td);
	}
	
	var selectLparDiv = $('<div id="selectLparDiv" style="margin: 20px;"></div>');
	var temp = 0;
	for (var i in selectLpar){
		temp ++;
		break;
	}
	
	//there is not selected lpars, show the info bar
	if (0 == temp){
		selectLparDiv.append(createInfoBar('Click CEC and select lpars to do operations.'));
	}
	//show selected lpars
	else{
		updateSelectLparDiv();
	}
	
	//add buttons
	var tempDiv = $('<div class="actionBar"></div>');
	tempDiv.append(createActionMenu());
	area.append(tempDiv);
	area.append(selectLparDiv);
	area.append(graphTable);
	
	$('.tooltip input[type = checkbox]').bind('click', function(){
		var lparName = $(this).attr('name');
		if ('' == lparName){
			return;
		}
		if (true == $(this).attr('checked')){
			selectLpar[lparName] = 1;
			$('#graphTable [name=' + lparName + ']').css('border-color', 'aqua');
		}
		else{
			delete selectLpar[lparName];
			$('#graphTable [name=' + lparName + ']').css('border-color', '#BDBDBD');
		}
		
		updateSelectLparDiv();
	});
	
	$('.fspDiv2, .fspDiv4, .fspDiv42').tooltip({
		position: "top center",
		relative : true,
		offset : [20, 40],
		effect: "fade"
	});
	
	$('.fspDiv2, .fspDiv4, .fspDiv42').bind('click', function(){
		var fspName = $(this).attr('value');
		showSelectDialog(fspList[fspName]['children']);
	});
}

/**
 * show the fsp's information in a dialog
 * 
 * @param fspName : fsp's name
 *        
 * @return
 */
function showSelectDialog(lpars){
	var diaDiv = $('<div class="tab" title=Select Lpars"></div>');
	
	if (0 == lpars.length){
		diaDiv.append(createInfoBar('There is not any lpars be selected(defined).'));
	}
	else{
		//add the dialog content
		var selectTable = $('<table id="selectLparTable"><tbody></tbody></table>');
		selectTable.append('<tr><th><input type="checkbox" onclick="selectAllLpars($(this))"></input></th><th>Name</th><th>Status</th></tr>');
		for (var lparIndex in lpars){
			var row = $('<tr></tr>');
			var lparName = lpars[lparIndex];
			var color = statusMap(lparList[lparName]);
			
			if (selectLpar[lparName]){
				row.append('<td><input type="checkbox" checked="checked" name="' + lparName + '"></input></td>');
			}
			else{
				row.append('<td><input type="checkbox" name="' + lparName + '"></input></td>');
			}
			row.append('<td>' + lparName + '</td>');
			row.append('<td style="background-color:' + color + ';">' + lparList[lparName] + '</td>');
			selectTable.append(row);
		}
		diaDiv.append(selectTable);
	}
	
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
	 				$('#selectLparTable input[type=checkbox]').each(function(){
	 					var lparName = $(this).attr('name');
	 					if ('' == lparName){
	 						//continue
	 						return true;
	 					}
	 					if (true == $(this).attr('checked')){
	 						selectLpar[lparName] = 1;
	 						$('#graphTable [name=' + lparName + ']').css('border-color', 'aqua');
	 					}
	 					else{
	 						delete selectLpar[lparName];
	 						$('#graphTable [name=' + lparName + ']').css('border-color', 'transparent');
	 					}
	 				});
	 				updateSelectLparDiv();
			     	$(this).dialog('close');
				 }
		}
	});
}

/**
 * update the lpars' background in cec, lpars area and  selectLpar
 * 
 * @param 
 * @return
 *
 **/
function updateSelectLparDiv(){
	var temp = 0;
	$('#selectLparDiv').empty();

	//add buttons
	
	$('#selectLparDiv').append('Lpars: ');
	for(var lparName in selectLpar){
		$('#selectLparDiv').append(lparName + ' ');
		temp ++;
		if (6 < temp){
			$('#selectLparDiv').append('...');
			break;
		}
	}
	
	var reselectButton = createButton('Reselect');
	$('#selectLparDiv').append(reselectButton);
	reselectButton.bind('click', function(){
		reselectLpars();
	});
	
}

/**
 * create the action menu
 * 
 * @param getNodesFunction
 *            the function that can find selected nodes name
 * @return 
 *        action menu object
 */
function createActionMenu(){
	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	/**
	 * The following actions are available to perform against a given node:
	 * power, clone, delete, unlock, and advanced
	 */
	/*
	 * Power
	 */
	var powerLnk = $('<a>Power</a>');

	/*
	 * Power on
	 */
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.bind('click', function(event) {
		var tgtNodes = getSelectLpars();
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rpower',
				tgt : tgtNodes,
				args : 'on',
				msg : ''
			}
		});
	});

	/*
	 * Power off
	 */
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.bind('click', function(event) {
		var tgtNodes = getSelectLpars();
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rpower',
				tgt : tgtNodes,
				args : 'off',
				msg : ''
			}
		});
	});

	/*
	 * Clone
	 */
	var cloneLnk = $('<a>Clone</a>');
	cloneLnk.bind('click', function(event) {
		var tgtNodes = getSelectLpars('nodesDataTable').split(',');
		for ( var i = 0; i < tgtNodes.length; i++) {
			var mgt = getNodeAttr(tgtNodes[i], 'mgt');
			
			// Create an instance of the plugin
			var plugin;
			switch(mgt) {
				case "blade":
		    		plugin = new bladePlugin();
		    		break;
				case "fsp":
					plugin = new fspPlugin();
					break;
				case "hmc":
					plugin = new hmcPlugin();
					break;
				case "ipmi":
					plugin = new ipmiPlugin();
					break;		
				case "ivm":
					plugin = new ivmPlugin();
					break;
				case "zvm":
					plugin = new zvmPlugin();
					break;
			}
			
			plugin.loadClonePage(tgtNodes[i]);
		}
	});

	/*
	 * Delete
	 */
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.bind('click', function(event) {
	});

	/*
	 * Unlock
	 */
	var unlockLnk = $('<a>Unlock</a>');
	unlockLnk.bind('click', function(event) {
	});

	/*
	 * Run script
	 */
	var scriptLnk = $('<a>Run script</a>');
	scriptLnk.bind('click', function(event) {
	});

	/*
	 * Update node
	 */
	var updateLnk = $('<a>Update</a>');
	updateLnk.bind('click', function(event) {
	});

	/*
	 * Set boot state
	 */
	var setBootStateLnk = $('<a>Set boot state</a>');
	setBootStateLnk.bind('click', function(event) {
	});

	/*
	 * Boot to network
	 */
	var boot2NetworkLnk = $('<a>Boot to network</a>');
	boot2NetworkLnk.bind('click', function(event) {
	});

	/*
	 * Open the Rcons page
	 */
	var rcons = $('<a>Open Rcons</a>');
	rcons.bind('click', function(event){
		var tgtNodes = getSelectLpars();
		if (tgtNodes) {
			loadRconsPage(tgtNodes);
		}
	});

	/*
	 * Advanced
	 */
	var advancedLnk = $('<a>Advanced</a>');

	// Power actions
	var powerActions = [ powerOnLnk, powerOffLnk ];
	var powerActionMenu = createMenu(powerActions);

	// Advanced actions
	var advancedActions;
	advancedActions = [ boot2NetworkLnk, scriptLnk, setBootStateLnk, updateLnk, rcons ];
	var advancedActionMenu = createMenu(advancedActions);

	/**
	 * Create an action menu
	 */
	var actionsDIV = $('<div></div>');
	var actions = [ [ powerLnk, powerActionMenu ], cloneLnk, deleteLnk, unlockLnk, [ advancedLnk, advancedActionMenu ] ];
	var actionMenu = createMenu(actions);
	actionMenu.superfish();
	actionsDIV.append(actionMenu);
	actionBar.append(actionsDIV);
	
	return actionBar;
}

/**
 * create the physical graphical layout 
 * 
 * @param bpaName : fsp's key
 *        fsp : all fsp and there related lpars
 *        fspinfo : all fsps' hardwareinfo
 * @return
 *       
 */
function createFspDiv(fspName, mtm, fsp){
	//create fsp title
	var lparStatusRow = '';
	
	for (var lparIndex in fsp[fspName]['children']){
		//show 8 lpars on one cec at most.
		if (lparIndex >= 8){
			break;
		}
		var lparName = fsp[fspName]['children'][lparIndex];
		var color = statusMap(lparList[lparName]);
		lparStatusRow += '<td class="lparStatus" style="background-color:' + color + ';color:' + color + ';padding: 0px;font-size:1;border-width: 1px;border-style: solid;" name="' + lparName + '">1</td>';
	}
	
	//select the backgroud
	var divClass = '';
	if (hardwareInfo[mtm][1]){
		divClass += 'fspDiv' + hardwareInfo[mtm][1];
	}
	else{
		divClass += 'fspDiv4';
	}
		
	//create return value
	var retHtml = '<div value="' + fspName + '" class="' + divClass + '">';
	retHtml += '<div class="lparDiv"><table><tbody><tr>' + lparStatusRow + '</tr></tbody></table></div></div>';
	return retHtml;
}

/**
 * create the physical graphical fsps' help witch could select the lpars. 
 * 
 * @param bpaName : fsp's key
 *        fsp : all fsp and there related lpars
 *        fspinfo : all fsps' hardwareinfo
 * @return
 *        
 */
function createFspTip(fspName, mtm, fsp){
	var tip = $('<div class="tooltip"></div>');
	var tempTable = $('<table><tbody></tbody></table>');
	if (hardwareInfo[mtm]){
		tip.append('<h3>' + fspName + '(' + hardwareInfo[mtm][0] + ')</h3><br/>');
	}
	else{
		tip.append('<h3>' + fspName + '</h3><br/>');
	}
	
	for (var lparIndex in fsp[fspName]['children']){
		var lparName = fsp[fspName]['children'][lparIndex];
		var color = statusMap(lparList[lparName]);
		var row = '<tr><td><input type="checkbox" name="' + lparName + '"></td>';
		row += '<td style="color:#fff">'+ lparName + '</td>';
		row += '<td style="background-color:' + color + ';color:#fff">' + lparList[lparName] + '</td></tr>';
		tempTable.append(row);
	}
	
	tip.append(tempTable);
	return tip;
}
/**
 * map the lpar's status into a color 
 * 
 * @param status : lpar's status in nodelist table

 * @return
 *        corresponding color name
 */
function statusMap(status){
	var color = 'gainsboro';
	
	switch(status){
		case 'alive':
		case 'ready':
		case 'pbs':
		case 'sshd':
		case 'booting':{
			color = 'green';
		}
		break;
		case 'noping':
		case 'unreachable':{
			color = 'red';
		}
		break;
		case 'ping':{
			color = 'yellow';
		}
		break;
		default:
			break;
	}
	
	return color;
}

/**
 * select all lpars checkbox in the dialog 
 * 
 * @param 

 * @return
 *        
 */
function selectAllLpars(checkbox){
	var temp = checkbox.attr('checked');
	$('#selectLparTable input[type = checkbox]').attr('checked', temp);
}

/**
 * export all lpars' name from selectLpar 
 * 
 * @param 

 * @return lpars' string
 *        
 */
function getSelectLpars(){
	var ret = '';
	for (var lparName in selectLpar){
		ret += lparName + ',';
	}
	
	return ret.substring(0, ret.length-1);
}

/**
 * show all lpars' for users to delete 
 * 
 * @param 

 * @return 
 */
function reselectLpars(){
	var temp = new Array();
	
	for (var lparName in selectLpar){
		temp.push(lparName);
	}
	
	showSelectDialog(temp);
}
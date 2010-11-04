

var bpaList;
var fspList;
var lparList;
var selectLpar = new Object();
/**
 * Get all nodes' nodetype and parent, and create the physical layout div
 * 
 * @param data: the response from xcat command "nodels all nodetype.nodetype ppc.parent ..." 
 *        area: the element to append tree and graphical layout
 * @return
 */
function createPhysicalLayout(data, area){
	var nodes = data.rsp;
	var tempList = new Object();
	bpaList = new Object();
	fspList = new Object();
	lparList = new Object();
	
	//extract useful info into tempList
	for (var i = 0; i < nodes.length; i++){
		var nodeName = nodes[i][0];
		if (undefined == tempList[nodeName]){
			tempList[nodeName] = new Object();
		}
		
		switch(nodes[i][2]){
			case 'nodetype.nodetype': {
				tempList[nodeName]['type'] = nodes[i][1];
			}
			break;
			case 'ppc.parent' : {
				tempList[nodeName]['parent'] = nodes[i][1];
			}
			break;
			case 'nodelist.status': {
				tempList[nodeName]['status'] = nodes[i][1];
			}
			break;
			case 'vpd.mtm': {
				tempList[nodeName]['mtm'] = nodes[i][1];
			}
			default :
				break;
		}
	}
	
	for (var nodeName in tempList){
		var parentName = tempList[nodeName]['parent'];
		var mtm = tempList[nodeName]['mtm'];
		var status = tempList[nodeName]['status'];
		switch(tempList[nodeName]['type']){
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
					fspList[parentName] = new Array();
					//default is 4 units. so i select a 4u mtm randomly
					fspList[parentName]['mtm'] = '8202-E4B';
					fspList[nodeName]['children'] = new Array();
				}
				
				fspList[parentName]['children'].push(nodeName);
				lparList[nodeName] = status;
			}
			break;
			case 'fsp': {
				if (undefined == fspList[nodeName]){
					fspList[nodeName] = new Array();
					fspList[nodeName]['children'] = new Array();
				}
				
				fspList[nodeName]['mtm'] = mtm;
				
				if ('' == parentName){
					break;
				}
				
				if (undefined == bpaList[parentName]){
					bpaList[parentName] = new Array();
				}
				
				bpaList[parentName].push(nodeName);
			}
			break;
			default:
				break;
		}
	}
	
	createTree(bpaList, fspList, area);
	createGraphical(bpaList, fspList, area);
	
}

/**
 * create the physical tree layout 
 * 
 * @param bpa : all bpa and there related  fsps
 *        fsp : all fsp and there related lpars
 *        area: the element to append tree layout
 * @return
 */
function createTree(bpa, fsp, area){
	//create tree and layout
	var usedFsp = new Object();
	var bpaList = '<ul>';
	for(var bpaName in bpa)
	{
		var fspList = '<ul>';
		for(var fspIndex in bpa[bpaName])
		{
			var fspName = bpa[bpaName][fspIndex];
			usedFsp[fspName] = 1;
			var lparList = '<ul>';
			for (var lparIndex in fsp[fspName]['children'])
			{
				lparList += '<li><ins>&nbsp;</ins>' + fsp[fspName]['children'][lparIndex] + '</li>';
			}
			lparList += '</ul>';
			fspList += '<li><a href="#">' + fspName + '(' + fsp[fspName]['children'].length + ' lpars)</a>' + lparList + '</li>';

		}
		fspList += '</ul>';
		bpaList += '<li><a href="#">' + bpaName + '(' + bpa[bpaName].length + ' fsps)</a>' + fspList + '</li>';
	}
	bpaList += '</ul>';
	
	var cecList = '<ul>';
	for (var fspName in fsp)
	{
		if (usedFsp[fspName])
		{
			continue;
		}
		var lparList = '<ul>';
		for (var lparIndex in fsp[fspName]['children'])
		{
			lparList += '<li><ins>&nbsp;</ins>' + fsp[fspName]['children'][lparIndex] + '</li>';
		}
		lparList += '</ul>';
		cecList += '<li><a href="#">' + fspName + '(' + fsp[fspName]['children'].length + ' lpars)</a>' + lparList + '</li>';
	}
	cecList += '</ul>';
	
	var tree_area = $('<div class="physicaltree"></div>');
	
	tree_area.append('<ul><li><a href="#">BPA</a>' + bpaList + '</li><li><a href="#">FSP</a>' + cecList + '</li></ul>');
	area.append(tree_area);
	tree_area.tree({});
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
	var graphField = $('<fieldset></fieldset>');
	graphField.append('<legend>Graphical Layout</legend>');
	var graphTable = $('<table id="graphTable"><tbody></tbody></table>');
	var elementNum = 0;
	var row;
	for (var bpaName in bpa){
		if (0 == elementNum % 3){
			row = $('<tr></tr>');
			graphTable.append(row);
		}
		elementNum ++;
		var td = $('<td></td>');
		var frameDiv = $('<div class="frameDiv"></div>');
		frameDiv.append('<div style="height:27px;">' + bpaName + '</div>');
		for (var fspIndex in bpa[bpaName]){
			var fspName = bpa[bpaName][fspIndex];
			usedFsp[fspName] = 1;
			
			frameDiv.append(createFspDiv(fspName, fsp[fspName]['mtm'], fsp));			
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

		var td = '<td style="vertical-align:top">' + createFspDiv(fspName, fsp[fspName]['mtm'], fsp) + '</td>';
		row.append(td);
	}
	
	graphField.append(graphTable);
	
	var graphical_area = $('<div class="physicalview"></div>');
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
	graphical_area.append(selectLparDiv);
	graphical_area.append(graphField);
	area.append(graphical_area);
	
	$('.fspDiv2, .fspDiv4, .fspDiv42').tooltip({

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
		diaDiv.append(createInfoBar('There is not any lpars defined.'));
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
				row.append('<td><input type="checkbox" checked="checked" id="' + lparName + '"></input></td>');
			}
			else{
				row.append('<td><input type="checkbox" id="' + lparName + '"></input></td>');
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
	 					var lparName = $(this).attr('id');
	 					if ('' == lparName){
	 						//continue
	 						return true;
	 					}
	 					if (true == $(this).attr('checked')){
	 						selectLpar[lparName] = 1;
	 						$('#graphTable #' + lparName).css('border-color', 'aqua');
	 					}
	 					else{
	 						delete selectLpar[lparName];
	 						$('#graphTable #' + lparName).css('border-color', 'transparent');
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
	
	for (var LparName in selectLpar){
		temp ++;
		break;
	}
	
	if (0 == temp){
		$('#selectLparDiv').append(createInfoBar('Click CEC and select lpars to do operations.'));
		return;
	}
	
	temp =0;
	//add buttons
	var tempDiv = $('<div class="actionBar"></div>');
	tempDiv.append(createActionMenu());
	$('#selectLparDiv').append(tempDiv);
	$('#selectLparDiv').append('<br/>Lpars: ');
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
 *        fspDiv's html
 */
function createFspDiv(fspName, mtm, fsp){
	//create fsp title
	var title = '<h3>' + fspName;
	var lparStatusRow = '';
	if (hardwareInfo[mtm]){
		title += '(' + hardwareInfo[mtm][0] + ')';
	}
	
	title += '</h3><br/>';
	
	for (var lparIndex in fsp[fspName]['children']){
		var lparName = fsp[fspName]['children'][lparIndex];
		var color = statusMap(lparList[lparName]);
		title += lparName + '<br/>';
		lparStatusRow += '<td class="lparStatus" style="background-color:' + color + ';color:' + color + ';" id="' + lparName + '">1</td>';
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
	var retHtml = '<div value="' + fspName + '" class="' + divClass + '" title="' + title + '">';
	retHtml += '<div class="lparDiv"><table><tbody><tr>' + lparStatusRow + '</tr></tbody></table></div>';
	return retHtml;
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
var bpaList;
var fspList;
var lparList;
var nodeList;
var selectNode;

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
			break;
			case 'nodehm.mgt': {
				nodeList[nodeName]['mgt'] = nodes[i][1];
			}
			break;
			default :
				break;
		}
	}	
}

function createPhysicalLayout(data){
	bpaList = new Object();
	fspList = new Object();
	lparList = new Object();
	selectNode = new Object();
	
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
		frameDiv.append('<div style="height:27px;" title="' + bpaName + '"><input type="checkbox" class="fspcheckbox" name="check_'+ bpaName +'"></div>');
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

		var td = $('<td style="padding:0;vertical-align:top;border-color: transparent;"></td>');
		td.append(createFspDiv(fspName, fsp[fspName]['mtm'], fsp));
		td.append(createFspTip(fspName, fsp[fspName]['mtm'], fsp));
		row.append(td);
	}
	
	var selectNodeDiv = $('<div id="selectNodeDiv" style="margin: 20px;">Nodes:</div>');
	var temp = 0;
	for (var i in selectNode){
		temp ++;
		break;
	}
	
	//there is not selected lpars, show the info bar
	if (0 == temp){
		area.append(createInfoBar('Hover over a CEC and select the LPARs to do operations against.'));
	}
	//show selected lpars
	else{
		updateSelectNodeDiv();
	}
	
	//add buttons
	area.append(createActionMenu());
	area.append(selectNodeDiv);
	area.append(graphTable);
	
	$('.tooltip input[type = checkbox]').bind('click', function(){
		var lparName = $(this).attr('name');
		if ('' == lparName){
			return;
		}
		if (true == $(this).attr('checked')){
			changeNode(lparName, 'select');
		}
		else{
			changeNode(lparName, 'unselect');
		}
		
		updateSelectNodeDiv();
	});
	
	$('.fspDiv2, .fspDiv4, .fspDiv42').tooltip({
		position: "center right",
		relative : true,
		offset : [10, 10],
		effect: "fade"
	});
	
	$('.tooltip a').bind('click', function(){
		var lparName = $(this).html();
		$('#nodesDatatable #' + lparName).trigger('click');
	});
	
	$('.fspDiv2, .fspDiv4, .fspDiv42').bind('click', function(){
		var fspName = $(this).attr('value');
		var selectCount = 0;
		for (var lparIndex in fspList[fspName]['children']){
			var lparName = fspList[fspName]['children'][lparIndex];
			if (selectNode[lparName]){
				selectCount ++;
			}
		}
		
		//all the lpars are selected, so unselect nodes
		if (selectCount == fspList[fspName]['children'].length){
			for (var lparIndex in fspList[fspName]['children']){
				var lparName = fspList[fspName]['children'][lparIndex];
				changeNode(lparName, 'unselect');
			}
		}
		//not select all lpars on the cec, so add all lpars into selectNode Hash.
		else{
			for (var lparIndex in fspList[fspName]['children']){
				var lparName = fspList[fspName]['children'][lparIndex];
				changeNode(lparName, 'select');
			}
		}
		
		updateSelectNodeDiv();
	});
	
	$('.fspcheckbox').bind('click', function(){
		var itemName = $(this).attr('name');
		name = itemName.substr(6);
		
		if ($(this).attr('checked')){
			selectNode[name] = 1;
		}
		else{
			delete selectNode[name];
		}
		
		updateSelectNodeDiv();
	});
}

/**
 * update the lpars' background in cec, lpars area and  selectNode
 * 
 * @param 
 * @return
 *
 **/
function updateSelectNodeDiv(){
	var temp = 0;
	$('#selectNodeDiv').empty();

	//add buttons
	
	$('#selectNodeDiv').append('Nodes: ');
	for(var lparName in selectNode){
		$('#selectNodeDiv').append(lparName + ' ');
		temp ++;
		if (6 < temp){
			$('#selectNodeDiv').append('...');
			break;
		}
	}
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
	var powerLnk = $('<a>Power</a>');
	//Power on
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
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

	//Power off
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
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

	//Clone
	var cloneLnk = $('<a>Clone</a>');
	cloneLnk.bind('click', function(event) {
		for (var name in selectNode) {
			var mgt = nodeList[name]['mgt'];
			
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
			
			plugin.loadClonePage(name);
		}
	});

	//Delete
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadDeletePage(tgtNodes);
		}
	});

	//Unlock
	var unlockLnk = $('<a>Unlock</a>');
	unlockLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadUnlockPage(tgtNodes);
		}
	});

	//Run script
	var scriptLnk = $('<a>Run script</a>');
	scriptLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadScriptPage(tgtNodes);
		}
	});

	//Update node
	var updateLnk = $('<a>Update</a>');
	updateLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadUpdatenodePage(tgtNodes);
		}
	});

	//Set boot state
	var setBootStateLnk = $('<a>Set boot state</a>');
	setBootStateLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadNodesetPage(tgtNodes);
		}
	});

	//Boot to network
	var boot2NetworkLnk = $('<a>Boot to network</a>');
	boot2NetworkLnk.bind('click', function(event) {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadNetbootPage(tgtNodes);
		}
	});

	//Remote console
	var rcons = $('<a>Open console</a>');
	rcons.bind('click', function(event){
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadRconsPage(tgtNodes);
		}
	});
	
	//Edit properties
	var editProps = $('<a>Edit properties</a>');
	editProps.bind('click', function(event){
		for (var node in selectNode) {
			loadEditPropsPage(node);
		}
	});

	var advancedLnk = $('<a>Advanced</a>');

	// Power actions
	var powerActions = [ powerOnLnk, powerOffLnk ];
	var powerActionMenu = createMenu(powerActions);

	// Advanced actions
	var advancedActions;
	advancedActions = [ boot2NetworkLnk, scriptLnk, setBootStateLnk, updateLnk, rcons, editProps ];
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
		lparStatusRow += '<td class="lparStatus" style="background-image:url(images/nodes/' + color + '.gif);padding: 0px;" name="' + lparName + '"></td>';
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
	var retHtml = '<input style="margin:3px 3px 1px 4px;padding:0;" class="fspcheckbox" type="checkbox" name="check_' + fspName + '">';
	retHtml += '<div value="' + fspName + '" class="' + divClass + '">';
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
		row += '<td style="color:#fff"><a>'+ lparName + '</a></td>';
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
			color = 'grey';
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
	$('#selectNodeTable input[type = checkbox]').attr('checked', temp);
}

/**
 * export all lpars' name from selectNode 
 * 
 * @param 

 * @return lpars' string
 *        
 */
function getSelectNodes(){
	var ret = '';
	for (var lparName in selectNode){
		ret += lparName + ',';
	}
	
	return ret.substring(0, ret.length-1);
}

/**
 * when the node is selected or unselected, then update the area on cec, update the global
 * list and update the tooltip table 
 * 
 * @param 

 * @return 
 */
function changeNode(lparName, status){
	var imgUrl = '';
	var checkFlag = true;
	if ('select' == status){
		selectNode[lparName] = 1;
		imgUrl = 'url(images/nodes/s-'+ statusMap(lparList[lparName]) + '.gif)';
		checkFlag = true;
	}
	else{
		delete selectNode[lparName];
		imgUrl = 'url(images/nodes/'+ statusMap(lparList[lparName]) + '.gif)';
		checkFlag = false;
	}
	$('#graphTable [name=' + lparName + ']').css('background-image', imgUrl);
	$('.tooltip input[name="' + lparName + '"]').attr('checked', checkFlag);
}
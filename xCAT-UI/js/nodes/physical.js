var bpaList;
var fspList;
var lparList;
var graphicalNodeList;
var selectNode;

/**
 * get all nodes useful attributes from remote server.
 * 
 * @param dataTypeIndex: the index in Array graphicalDataType, which contains attributes we need.
 * 		  attrNullNode:  the target node list for this attribute 
 *
 * @return null
 */
function initGraphicalData(){
	$('#graphTab').append(createLoader());
	$.ajax( {
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
			extractGraphicalData(data.rsp[0]);
			getNodesAndDraw();
		}
	});
}

/**
 * extract all nodes userful data into a hash, which is used for creating graphical
 * 
 * @param data: the response from xcat command "nodels all nodetype.nodetype ppc.parent ..." 
 * @return nodes list for next time query
 */
function extractGraphicalData(data){
	var nodes = data.split(';');
	var attrs;
	var nodename;
	//extract useful info into tempList
	for (var i = 0; i < nodes.length; i++){
		attrs = nodes[i].split(':');
		nodename = attrs[0];
		if (undefined == graphicalNodeList[nodename]){
			graphicalNodeList[nodename] = new Object();
		}
		switch(attrs[1].toLowerCase()){
			case 'cec':
			case 'frame':
			case 'lpar':
			case 'lpar,osi':
			case 'osi,lpar':
				graphicalNodeList[nodename]['type'] = attrs[1];
				graphicalNodeList[nodename]['parent'] = attrs[2];
				graphicalNodeList[nodename]['mtm'] = attrs[3];
				graphicalNodeList[nodename]['status'] = attrs[4];
				break;
			case 'blade':
				graphicalNodeList[nodename]['type'] = attrs[1];
				graphicalNodeList[nodename]['mpa'] = attrs[2];
				graphicalNodeList[nodename]['unit'] = attrs[3];
				graphicalNodeList[nodename]['status'] = attrs[4];
				break;
			case 'systemx':
				graphicalNodeList[nodename]['type'] = attrs[1];
				graphicalNodeList[nodename]['rack'] = attrs[2];
				graphicalNodeList[nodename]['unit'] = attrs[3];
				graphicalNodeList[nodename]['mtm'] = attrs[4];
				graphicalNodeList[nodename]['status'] = attrs[5];
				break;
			default:
				break;
		}
	}
}

function createPhysicalLayout(nodeList){
	var flag = false;
	
	//when the graphical layout is shown, do not need to redraw
	if (1 < $('#graphTab').children().length){
		return;
	}
	
	//save the new selected nodes.
	if (graphicalNodeList){
		for(var i in graphicalNodeList){
			flag = true;
			break;
		}
	}
	
    bpaList = new Object();
    fspList = new Object();
    lparList = new Object();
    selectNode = new Object();
    
	//there is not graphical data, get the info now
	if (!flag){
		graphicalNodeList = new Object();
		initGraphicalData();
	}
	else{
		getNodesAndDraw();
	}
}

function getNodesAndDraw(){
	var groupname = $.cookie('selectgrouponnodes');
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'nodels',
			tgt : groupname,
			args : '',
			msg : ''
		},
		success : function(data){
			for (var temp in data.rsp){
				var nodeName = data.rsp[temp][0];
				if ('' == nodeName){
					continue;
				}
				fillList(nodeName);
			}
			$('#graphTab').empty();
			createGraphical(bpaList, fspList, $('#graphTab'));
		}
	});
}

function fillList(nodeName, defaultnodetype){
    var parentName = '';
    var mtm = '';
    var status = '';
    var nodetype = '';
    if (!graphicalNodeList[nodeName]){
        parentName = '';
        mtm = '';
        status = '';
        nodetype = defaultnodetype;
    }
    else{
        parentName = graphicalNodeList[nodeName]['parent'];
        mtm = graphicalNodeList[nodeName]['mtm'];
        status = graphicalNodeList[nodeName]['status']; 
        nodetype = graphicalNodeList[nodeName]['type'];
    }
    
	if ('' == status){
		status = 'unknown';
	}
	
	switch (nodetype){
		case 'frame': {
			if (undefined == bpaList[nodeName]){
				bpaList[nodeName] = new Array();
			}
		}
		break;
		case 'lpar,osi': 
		case 'lpar':
		case 'osi': {
			if ('' == parentName){
				break;
			}
			
			if (undefined == fspList[parentName]){
				fillList(parentName, 'cec');
			}
			
			fspList[parentName]['children'].push(nodeName);
			lparList[nodeName] = status;
		}
		break;
		case 'cec': {
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
				fillList(parentName, 'frame');
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
		
		//for P7-IH, all the cecs are insert into the frame from down to up, so we had to show the cecs same as the
		//physical layout.
		var tempBlankDiv = $('<div></div>');
		var tempHeight = 0;
		for (var fspIndex in bpa[bpaName]){
			var fspName = bpa[bpaName][fspIndex];
			usedFsp[fspName] = 1;			
			
			//this is the p7IH, we should add the blank at the top
			if ((0 == fspIndex) && ('9125-F2C' == fsp[fspName]['mtm'])){
				frameDiv.append(tempBlankDiv);
			}
			frameDiv.append(createFspDiv(fspName, fsp[fspName]['mtm'], fsp));
			frameDiv.append(createFspTip(fspName, fsp[fspName]['mtm'], fsp));
			
			tempHeight += coculateBlank(fsp[fspName]['mtm']);
		}
		
		//now the tempHeight are all cecs' height, so we should minus bpa div height and cecs' div height
		tempHeight = 428 - tempHeight;
		tempBlankDiv.css('height', tempHeight);
		td.append(frameDiv);
		row.append(td);
	}
	
	//find the single fsp and sort descend by units 
	var singleFsp = new Array();
	for (var fspName in fsp){
		if (usedFsp[fspName]){
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
		offset : [10, -40],
		effect: "fade",
		opacity: 0.9
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
 * @return action menu object
 */
function createActionMenu(){
	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	// Power on
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.click(function() {
		var tgtNodes = getSelectNodes();
		$.ajax({
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
	
	// Power off
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.click(function() {
		var tgtNodes = getSelectNodes();
		$.ajax({
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
	
	// Delete
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadDeletePage(tgtNodes);
		}
	});

	// Unlock
	var unlockLnk = $('<a>Unlock</a>');
	unlockLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadUnlockPage(tgtNodes);
		}
	});

	// Run script
	var scriptLnk = $('<a>Run script</a>');
	scriptLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadScriptPage(tgtNodes);
		}
	});

	// Update
	var updateLnk = $('<a>Update</a>');
	updateLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadUpdatenodePage(tgtNodes);
		}
	});

	// Set boot state
	var setBootStateLnk = $('<a>Set boot state</a>');
	setBootStateLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadNodesetPage(tgtNodes);
		}
	});

	// Boot to network
	var boot2NetworkLnk = $('<a>Boot to network</a>');
	boot2NetworkLnk.click(function() {
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadNetbootPage(tgtNodes);
		}
	});
	
	// Remote console
	var rconLnk = $('<a>Open console</a>');
	rconLnk.bind('click', function(event){
		var tgtNodes = getSelectNodes();
		if (tgtNodes) {
			loadRconsPage(tgtNodes);
		}
	});
	
	// Edit properties
	var editProps = $('<a>Edit properties</a>');
	editProps.bind('click', function(event){
		for (var node in selectNode) {
			loadEditPropsPage(node);
		}
	});
	
	// Actions
	var actionsLnk = '<a>Actions</a>';
	var actsMenu = createMenu([deleteLnk, powerOnLnk, powerOffLnk, scriptLnk]);

	// Configurations
	var configLnk = '<a>Configuration</a>';
	var configMenu = createMenu([unlockLnk, updateLnk, editProps]);

	// Provision
	var provLnk = '<a>Provision</a>';
	var provMenu = createMenu([boot2NetworkLnk, setBootStateLnk, rconLnk]);

	// Create an action menu
	var actionsMenu = createMenu([ [ actionsLnk, actsMenu ], [ configLnk, configMenu ],  [ provLnk, provMenu ] ]);
	actionsMenu.superfish();
	actionsMenu.css('display', 'inline-block');
	actionBar.append(actionsMenu);
	actionBar.css('margin-top', '10px');
	
	// Set correct theme for action menu
	actionsMenu.find('li').hover(function() {
		setMenu2Theme($(this));
	}, function() {
		setMenu2Normal($(this));
	});
	
	return actionBar;
}

/**
 * create the physical graphical layout 
 * 
 * @param bpaName : fsp's key
 *        fsp : all fsp and there related lpars
 *        fspinfo : all fsps' hardwareinfo
 * @return     
 */
function createFspDiv(fspName, mtm, fsp){
	//create fsp title
	var lparStatusRow = '';
	var temp = '';
	
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
	if ('' == mtm){
		temp = '8231-E2B';
	}
	else{
		temp = mtm;
	}
	if (hardwareInfo[temp][1]){
		divClass += 'fspDiv' + hardwareInfo[temp][1];
	}
	else{
		divClass += 'fspDiv4';
	}
		
	//create return value
	var retHtml = '<input style="padding:0;" class="fspcheckbox" type="checkbox" name="check_' + fspName + '">';
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
 */
function createFspTip(fspName, mtm, fsp){
	var tip = $('<div class="tooltip"></div>');
	var tempTable = $('<table><tbody></tbody></table>');
	var temp = '';
	if ('' == mtm){
		temp = 'unkown';
	}
	else{
		temp = mtm;
	}
	
	if (hardwareInfo[temp]){
		tip.append('<h3>' + fspName + '(' + hardwareInfo[temp][0] + ')</h3><br/>');
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
 * @return corresponding color name
 */
function statusMap(status){
	var color = 'gainsboro';
	
	switch(status){
		case 'alive':
		case 'ready':
		case 'pbs':
		case 'sshd':
		case 'booting':
		case 'ping':{
			color = 'green';
		}
		break;
		case 'noping':
		case 'unreachable':{
			color = 'red';
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
 */
function getSelectNodes() {
    var ret = '';
    for ( var lparName in selectNode) {
        ret += lparName + ',';
    }

    return ret.substring(0, ret.length - 1);
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

/**
 * The P7-IH's cecs are insert from down to up, so we had to coculate the blank height. 
 * 
 * @param 
 * @return the height for the cec
 */
function coculateBlank(mtm){
	if ('' == mtm){
		return 24;
	}
	
	if (!hardwareInfo[mtm]){
		return 24;
	}
	
	switch(hardwareInfo[mtm]){
		case 1:
		{
			return 13;
		}
		break;
		case 2:
		{
			return 24;
		}
		break;
		case 4:
		{
			return 47;
		}
		break;
		default:
			return 0;
		break;
	}
}
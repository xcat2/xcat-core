var bpaList;
var fspList;
var lparList;
var bladeList;
var rackList;
var unknownList;
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
		graphicalNodeList[nodename]['type'] = attrs[1].toLowerCase();
		switch(attrs[1].toLowerCase()){
			case 'cec':
			case 'frame':
			case 'lpar':
			case 'lpar,osi':
			case 'osi,lpar':
				graphicalNodeList[nodename]['parent'] = attrs[2];
				graphicalNodeList[nodename]['mtm'] = attrs[3];
				graphicalNodeList[nodename]['status'] = attrs[4];
				break;
			case 'blade':
				graphicalNodeList[nodename]['mpa'] = attrs[2];
				graphicalNodeList[nodename]['unit'] = attrs[3];
				graphicalNodeList[nodename]['status'] = attrs[4];
				break;
			case 'systemx':
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
    bladeList = new Object();
    selectNode = new Object();
    rackList = new Object();
    unknownList = new Array();
    
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
			createGraphical();
		}
	});
}

function fillList(nodeName, defaultnodetype){
    var parentName = '';
    var mtm = '';
    var status = '';
    var nodetype = '';
    var mpa = '';
    var unit = '';
    var rack = '';
    if (!graphicalNodeList[nodeName]){
        parentName = '';
        mtm = '';
        status = '';
        nodetype = defaultnodetype;
    }
    else{
    	status = graphicalNodeList[nodeName]['status']; 
        nodetype = graphicalNodeList[nodeName]['type'];
    	switch (nodetype){
	    	case 'frame':
	    	case 'lpar,osi': 
			case 'lpar':
			case 'osi':
			case 'cec':{
				parentName = graphicalNodeList[nodeName]['parent'];
		        mtm = graphicalNodeList[nodeName]['mtm'];
			}
			break;
			case 'blade':{
				mpa = graphicalNodeList[nodeName]['mpa'];
				unit = graphicalNodeList[nodeName]['unit'];
			}
			break;
			case 'systemx':{
				rack = graphicalNodeList[nodeName]['rack'];
				unit = graphicalNodeList[nodeName]['unit'];
			}
			break;
			default:
				break;
    	}
        
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
			
			fspList[nodeName] = new Object();
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
		case 'blade': {
			if (undefined == bladeList[mpa]){
				bladeList[mpa] = new Array();
			}
			bladeList[mpa].push(nodeName + ',' + unit);
		}
		break;
		case 'systemx':{
			if (!rack){
				rack = '_notsupply_';
			}
			if (undefined == rackList[rack]){
				rackList[rack] = new Array();
			}
			rackList[rack].push(nodeName + ',' + unit);
		}
		break;
		default:
			unknownList.push(nodeName);
			break;
	}
}

function createGraphical(){
	var tabarea = $('#graphTab');
	var selectNodeDiv = $('<div id="selectNodeDiv" style="margin: 20px;">Nodes:</div>');
	var temp = 0;
	for (var i in selectNode){
		temp ++;
		break;
	}
	
	//there is not selected lpars, show the info bar
	if (0 == temp){
		tabarea.append(createInfoBar('Hover over a CEC and select the LPARs to do operations against.'));
	}
	//show selected lpars
	else{
		updateSelectNodeDiv();
	}
	
	//add buttons
	tabarea.append(createActionMenu());
	tabarea.append(selectNodeDiv);
	createSystempGraphical(bpaList, fspList, tabarea);
	createBladeGraphical(bladeList, tabarea);
	createSystemxGraphical(rackList, tabarea);
	addUnknownGraphical(unknownList, tabarea);
}
/**
 * create the physical graphical layout for system p machines
 * 
 * @param bpa : all bpa and there related  fsps
 *        fsp : all fsp and there related lpars
 *        fspinfo : all fsps' hardwareinfo
 *        area: the element to append graphical layout
 * @return
 */
function createSystempGraphical(bpa, fsp, area){
	var usedFsp = new Object();
	var graphTable = $('<table style="border-color: transparent;margin:0px 0px 10px 0px;" ></table>');
	var elementNum = 0;
	var row;
	var showflag = false;
	
	//there is node in bpa list, so show add the title and show all frames
	for (var bpaName in bpa){
		showflag = true;
		$('#graphTab').append('system p<hr/>');
		$('#graphTab').append(graphTable);
		break;
	}
	
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
	
	//if there is not frame, so we should check if there is single cec and show the title and add node area.
	if (!showflag){
		for(var fspIndex in singleFsp){
			$('#graphTab').append('system p<hr/>');
			$('#graphTab').append(graphTable);
			break;
		}
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
 * create the physical graphical layout for blades
 * 
 * @param blades : the blade list in global 
 *        area: the element to append graphical layout
 * @return
 */
function createBladeGraphical(blades, area){
	var graphTable = $('<table style="border-color: transparent;margin:0px 0px 10px 0px;"></table>');
	var mpa = '';
	var bladename = '';
	var index = 0;
	var mpaNumber = 0;
	var row;
	var showflag = false;
	
	//only show the title and nodes when there are blade in the blade list
	for (mpa in blades){
		showflag = true;
		break;
	}
	
	if (showflag){
		$('#graphTab').append('Blade<hr/>');
		$('#graphTab').append(graphTable);
	}
	//if there is not blade nodes, return directly
	else{
		return;
	}
	
	for (mpa in blades){
		var tempArray = new Array(14);
		var bladeInfo = new Array();
		var unit = 0;
		if (0 == mpaNumber % 3){
			row = $('<tr></tr>');
			graphTable.append(row);
		}
		
		mpaNumber ++;
		
		var td = $('<td style="padding:0;border-color: transparent;"></td>');
		var chasisDiv = $('<div class="chasisDiv" title=' + mpa + '></div></div>');
		
		
		//fill the array with blade information, to create the empty slot
		for (index in blades[mpa]){
			bladeInfo = blades[mpa][index].split(',');
			unit = parseInt(bladeInfo[1]);
			tempArray[unit - 1] = bladeInfo[0];
			
		}
		
		//draw the blades and empty slot in chasis
		for (index = 0; index < 14; index++){
			if (tempArray[index]){
				bladename = tempArray[index];
				chasisDiv.append('<div id="' + bladename + '" class="bladeDiv bladeInsertDiv" title="' + bladename + '"></div>');
			}
			else{
				chasisDiv.append('<div class="bladeDiv"></div>');
			}
		}
		
		td.append(chasisDiv);
		row.append(td);
	}
	
}

/**
 * create the physical graphical layout for system x machines
 * 
 * @param xnodes : the system x node list in global 
 *        area: the element to append graphical layout
 * @return
 */
function createSystemxGraphical(xnodes, area){
	var graphTable = $('<table style="border-color: transparent;margin:0px 0px 10px 0px;"></table>');
	var xnodename = '';
	var index = 0;
	var rack = '';
	var row;
	var xnodenum = 0;
	var showflag = false;
	
	//only the title and system x node when there is x nodes in the list
	for (rack in rackList){
		showflag = true;
		break;
	}
	
	if (showflag){
		$('#graphTab').append('system x<hr/>');
		$('#graphTab').append(graphTable);
	}
	//there is nothing to show, return directly
	else{
		return;
	}

	for (rack in rackList){
		for(index in rackList[rack]){
			var xnodename = rackList[rack][index];
			if (0 == xnodenum % 3){
				row = $('<tr></tr>');
				graphTable.append(row);
			}
			xnodenum++;
			var td = $('<td style="padding:0;border-color: transparent;"></td>');
			var xnodeDiv = '<div id="' + xnodename + '" class="xnodeDiv" title="' + xnodename +'"></div>';
			td.append(xnodeDiv);
			row.append(td);
		}
	}
}

function addUnknownGraphical(unknownnode, area){
	var graphTab = $('#graphTab');
	var index = 0;
	
	if (unknownnode.length < 1){
		return;
	}
	
	graphTab.append('Unknown Type Nodes:<hr/>');
	for (index in unknownnode){
		graphTab.append(unknownnode[index] + '; ');
	}
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
		lparStatusRow += '<td class="lparStatus" style="background-image:url(images/nodes/' + color + '.gif);padding: 0px;" id="' + lparName + 'status"></td>';
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
		case 'booted':
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
	$('#' + lparName + 'status').css('background-image', imgUrl);
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
	
	switch(hardwareInfo[mtm][1]){
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
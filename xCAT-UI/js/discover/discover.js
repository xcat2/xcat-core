/*associate the step name with step number*/
var steps = ['Discover Hardware', 
             'Cluster Patterns',
             'Switch Ports',
             'More Cluster Patterns',
             'Prepare Management Node',
             'Power On Hardware',
             'Discover HW Control Points',
             'Update Definitions',
             'Configure HW Control Points',
             'Create Nodes',
             'Complete'];

/*associate the function with step number*/
var initFunctions = [initSelectPlatform,
                     initBasicPattern,
                     initSwitch,
                     initAdvancedPattern];

/*associate the function witch should be called before the page changed(when click next or back)
 * if there is no need to call functions, use undefined.*/
var nextFunctions = [undefined,
                     collectInputValue,
                     collectInputValue,
                     collectInputValue];
/*save current step number*/
var currentStep = 0;

/*save user's input*/
var discoverEnv;

/**
 * create the discover page
 * 
 * @param 
 * 
 * @return
 */
function loadDiscoverPage(){
	currentStep = 0;
	discoverEnv = new Object();
	$('#content').append('<div class="discoverstep" id="discoverStepDiv"></div>');
	updateDiscoverStep();
	
	$('#content').append('<div class="discovercontent" id="discoverContentDiv"><div>');
	initSelectPlatform();
}

/**
 * update the step show are on the left side of discover page
 * 
 * @param 
 * 
 * @return
 */
function updateDiscoverStep(){
	$('#discoverStepDiv').empty();
	var showString = '';
	for(var index in steps){
		showString += '<span';
		if (currentStep == index){
			showString += ' style="background-color:yellow;"';
		}
		showString += '>' + steps[index] + '</span><br/>';
	}
	$('#discoverStepDiv').html(showString);
}

/**
 * create the navigator buttons on the bottom of discover page
 * 
 * @param 
 * 
 * @return
 */
function createDiscoverButtons(){
	var buttonDiv = $('<div style="text-align:center;padding:20px 0px 10px 0px;"></div>');
	var backButton = createBackButton();
	var nextButton = createNextButton();
	var cancelButton = createButton('Cancel');
	cancelButton.bind('click', function(){
		$('#content').empty();
		for (var name in discoverEnv){
			delete discoverEnv[name];
		}
		loadDiscoverPage();
	});
	
	if (backButton){
		buttonDiv.append(backButton);
	}
	
	if(nextButton){
		buttonDiv.append(nextButton);
	}

	buttonDiv.append(cancelButton);
	$('#discoverContentDiv').append(buttonDiv);
}

/**
 * create the next button base on the currentStep, the last step does not need this button
 * 
 * @param 
 * 
 * @return
 */
function createNextButton(){
	if ((steps.length - 1) == currentStep){
		return undefined;
	}
	
	var nextButton = createButton('Next');
	nextButton.bind('click', function(){
		if (nextFunctions[currentStep]){
			nextFunctions[currentStep]();
		}
		currentStep ++;
		updateDiscoverStep();
		initFunctions[currentStep]();
	});
	
	return nextButton;
}

/**
 * create the next button base on the currentStep, the first step does not need this button
 * 
 * @param 
 * 
 * @return
 */
function createBackButton(){
	if (0 == currentStep){
		return undefined;
	}
	
	var backButton = createButton('Back');
	backButton.bind('click', function(){
		if (nextFunctions[currentStep]){
			nextFunctions[currentStep]();
		}
		currentStep--;
		updateDiscoverStep();
		initFunctions[currentStep]();
	});
	
	return backButton;
}

/**
 * get the input value on discover page
 * 
 * @param 
 *        envName :  value's name(discoverEnv's key)
 * 
 * @return
 *       if there is assciate value, return the value. 
 *       else return null.
 */
function getDiscoverEnv(envName){
	if (discoverEnv[envName]){
		return discoverEnv[envName];
	}
	else{
		return '';
	}
}
/**
 * Expand the noderange into node names.
 * 
 * @param 
 *        nodeRange :  
 * 
 * @return
 *       node names array.
 *       
 */
function expandNR(nodeRange){
	var retArray = new Array();
	var tempResult;
	if ('' == nodeRange){
		return retArray;
	}
	
	tempResult = nodeRange.match(/(.*?)\[(.*?)\](.*)/);
	if (null != tempResult){
		var parts = tempResult[2].split('-');
		if (2 > parts.length){
			return retArray;
		}
		
		var start = Number(parts[0]);
		var end = Number(parts[1]);
		var len = parts[0].length;
		for(var i = parts[0]; i <= parts[1]; i++){
			var ts = i.toString();
			if (ts.length < len){
				ts = "000000".substring(0, (len - ts.length)) + ts;
			}
			retArray = retArray.concat(expandNR(tempResult[1] + ts + tempResult[3]));
		}
		return retArray;
	}
	
	var tempArray = nodeRange.split('-');
	if (2 > tempArray.length){
		retArray.push(nodeRange);
		return retArray;
	}
	
	var begin = tempArray[0].match(/^(\D+)(\d+)$/);
	if(2 > begin){
		retArray.push(nodeRange);
		return retArray;
	}
	
	var end = tempArray[1].match(/^(\D+)(\d+)$/);
	if(2 > end){
		retArray.push(nodeRange);
		return retArray;
	}
	
	if(begin[1] != end[1]){
		retArray.push(nodeRange);
		return retArray;
	}
	
	var prefix = begin[1];
	var len = begin[2].length;
	for(var i = begin[2]; i <= end[2]; i++){
		var ts = i.toString();
		if (ts.length < len){
			ts = "000000".substring(0, (len - ts.length)) + ts;
		}
		retArray.push(prefix + ts);
	}
	
	return retArray;
}

/**
 * Step 1: show the wizard's function 
 *         platform selector(system P or system X)
 * 
 * @param 
 * 
 * @return
 */
function initSelectPlatform(){
	var temp = '';
	$('#discoverContentDiv').empty();
	temp += '<h2>' + steps[currentStep] + '</h2>';
	temp += '<p>This wizard will guide you through the process of defining the naming conventions within' + 
		'your cluster, discovering the hardware on your network, and automatically defining it in the xCAT' +
		'database.<br/>Choose which type of hardware you want to discover, and then click Next.</p>';
	
	temp += '<input type="radio" name="platform" disabled="true"><span  style="color:gray;"> System x hardware (not implemented yet)</span></input><br/>';
	temp += '<input type="radio" name="platform" checked="checked"> System p hardware (only partially implemented)</input><br/>';
	temp += '<br/><br/><br/><br/><br/>';
	$('#discoverContentDiv').append(temp);
	
	createDiscoverButtons();
}

/**
 * Step 2: Cluster basic patterns 
 *         users can input the switches' name range, the number of port, start ip and port prefix
 *                             hmcs' name range, number and start ip
 *                             frames' name range, number and start ip
 *                             drawers' name range, number and start ip
 * 
 * @param 
 * 
 * @return
 */
function initBasicPattern(){
	$('#discoverContentDiv').empty();
	var showString = '<h2>' + steps[currentStep] + '</h2>';
	showString += '<table><tbody>';
	//switch title
	showString += '<tr><th colspan=5>Service LAN Switches</th></tr>';
	//switch name 
	showString += '<tr><td>Hostname Range:</td><td><input type="text" title="Format: Node[1-10] or Node1-Node10" name="switchName" value="' + getDiscoverEnv('switchName') + '"></input></td>';
	showString += '<td width=20></td>';
	//switch start ip	
	showString += '<td>Starting IP Address:</td><td><input type="text" name="switchIp" value="' + getDiscoverEnv('startIp') + '"></td></tr>';
	//Number of Ports Per Switch
	showString += '<tr><td>Number of Ports Per Switch:</td><td><input type="text" name="portNumPerSwitch" value="' + getDiscoverEnv('portNumPerSwitch') + '"></td>';
	showString += '<td width=20></td>';
	//ports' name prefix
	showString += '<td>Switch Port Prefix:</td><td><input type="text" title="a" name="portPrefix" value="' + getDiscoverEnv('portPrefix') + '"></td></tr>';
	//hmc title
	showString += '<tr><th colspan=5>HMCs</th></tr>';
	//hmc name
	showString += '<tr><td>Hostname Range:</td><td><input type="text" title="Format: Node[1-10] or Node1-Node10" name="hmcName" value="' + getDiscoverEnv('hmcName') + '"></td>';
	showString += '<td width=20></td>';
	//hmc start ip
	showString += '<td>Starting IP Address:</td><td><input type="text" name="hmcIp" value="' + getDiscoverEnv('hmcIp') + '"></td></tr>';
	//Number of Frames per HMC
	showString += '<tr><td>Number of Frames per HMC:</td><td><input type="text" name="bpaNumPerHmc" value="' + getDiscoverEnv('bpaNumPerHmc') + '"></td></tr>';
	//BPA title
	showString += '<tr><th colspan=5>Frames (BPAs)</th></tr>';
	//BPA Name
	showString += '<tr><td>Hostname Range:</td><td><input type="text" title="Format: Node[1-10] or Node1-Node10" name="bpaName" value="' + getDiscoverEnv('bpaName') + '"></td>';
	showString += '<td width=20></td>';
	//BPA start ip
	showString += '<td>Starting IP Address:</td><td><input type="text" name="bpaIp" value="' + getDiscoverEnv('bpaIp') + '"></td></tr>';
	//Number of Drawers per Frame
	showString += '<tr><td>Number of Drawers per Frame:</td><td><input type="text" name="fspNumPerBpa" value="' + getDiscoverEnv('fspNumPerBpa') + '"></td></tr>';
	//FSP title
	showString += '<tr><th colspan=5>Drawers (FSPs/CECs)</th></tr>';
	//FSP name
	showString += '<tr><td>Hostname Range:</td><td><input type="text" title="Format: Node[1-10] or Node1-Node10" name="fspName" value="' + getDiscoverEnv('fspName') + '"></td>';
	showString += '<td width=20></td>';
	//FSP start ip
	showString += '<td>Starting IP Address:</td><td><input type="text" name="fspIp" value="' + getDiscoverEnv('fspIp') + '"></td></tr>';
	//Number of LPARs per Drawer:
	showString += '<tr><td>Number of LPARs per Drawer:</td><td><input type="text" name="lparNumPerFsp" value="' + getDiscoverEnv('lparNumPerFsp') + '"></td></tr>';
	showString += '</tbody></table>';
	$('#discoverContentDiv').append(showString);
	$('#discoverContentDiv input[type=text][title]').tooltip({
		position: "center right",
		offset: [-2, 10],
		effect: "fade",
		opacity: 1
	});
	createDiscoverButtons();
}

/**
 * Step 2: Cluster basic patterns 
 *         save all of users' input into the global object discoverEnv
 * 
 * @param 
 * 
 * @return
 */
function collectInputValue(){
	$('#discoverContentDiv input[type=text]').each(function(){
		var name = $(this).attr('name');
		var value = $(this).attr('value');
		if('' != value){
			discoverEnv[name] = value;
		}
		else{
			if(discoverEnv[name]){
				delete discoverEnv[name];
			}
		}
	});
	
	return;
}

/**
 * Step 3: define switch ports  
 *          
 * @param 
 * 
 * @return
 */
function initSwitch(){
	$('#discoverContentDiv').empty();
	var showString = '<h2>' + steps[currentStep] + '</h2>';
	showString += '<table><tbody>';
	//Discovery Information title
	showString += '<tr><th colspan=5>Switch Port Assignments</th></tr>';
	//Dynamic IP Range for DHCP
	showString += '<tr><td>Dynamic IP Range for DHCP:</td><td><input type="text" name="ipRange" value="' + getDiscoverEnv('ipRange') + '"></td>';
	showString += '<td width=20></td>';
	//IP Address to Broadcast
	showString += '<td>IP Address to Broadcast From:</td><td><input type="text" name="broadcastIp" value="' + getDiscoverEnv('broadcastIp') + '"></td></tr>';
	showString += '</tbody></table>';
	$('#discoverContentDiv').append(showString);
	createDiscoverButtons();
}

function initAdvancedPattern(){
	$('#discoverContentDiv').empty();
	var showString = '<h2>' + steps[currentStep] + '</h2>';
	showString += '<table><tbody>';
	showString += '<tr><th colspan=5>Building Blocks</th></tr>';
	//Starting Subnet IP for Cluster Mgmt LAN:
	showString += '<tr><td>Starting Subnet IP for Cluster Mgmt LAN:</td><td><input type="text" name="MgmtIp" value="' + getDiscoverEnv('MgmtIp') + '"></td>';
	showString += '<td width=20></td>';
	//Compute Node Hostname Range
	showString += '<td>Compute Node Hostname Range:</td><td><input type="text" name="cnName" value="' + getDiscoverEnv('cnName') + '"></td></tr>';
	showString += '</tbody></table>';
	$('#discoverContentDiv').append(showString);
	createDiscoverButtons();
}
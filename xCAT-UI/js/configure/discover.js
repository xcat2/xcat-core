/*associate the step name with step number*/
var steps = ['Platform', 'Complete'];

/*associate the function with step number*/
var initFunctions = [initSelectPlatform, complete];

/*associate the function witch should be called before the page changed(when click next or back)
 *if there is no need to call functions, use undefined.*/
var nextFunctions = [getPlatform, undefined];

/*save current step number*/
var currentStep = 0;

/*save user's input*/
var discoverEnv;

/**
 * create the discover page
 * 
 * @return nothing
 */
function loadDiscoverPage(){
	currentStep = 0;
	discoverEnv = new Object();
	
	$('#discoverTab').append('<div class="discovercontent" id="discoverContentDiv"><div>');
	initSelectPlatform();
}

/**
 * create the navigator buttons on the bottom of discover page
 * 
 * @param 
 * 
 * @return nothing
 */
function createDiscoverButtons(){
	var buttonDiv = $('<div style="text-align:center;padding:20px 0px 10px 0px;"></div>');
	var backButton = createBackButton();
	var nextButton = createNextButton();
	var cancelButton = createButton('Cancel');
	cancelButton.bind('click', function(){
		$('#discoverTab').empty();
		for (var name in discoverEnv){
			removeDiscoverEnv(name);
		}
		loadDiscoverPage();
	});
	
	if (backButton){
		buttonDiv.append(backButton);
	}
	
	if (nextButton){
		buttonDiv.append(nextButton);
	}

	buttonDiv.append(cancelButton);
	$('#discoverContentDiv').append(buttonDiv);
}

/**
 * create the next button base on the currentStep, the last step does not need this button
 * 
 * @return nothing
 */
function createNextButton(){
	var tempFlag = true;
	if ((steps.length - 1) == currentStep){
		return undefined;
	}
	
	var nextButton = createButton('Next');
	nextButton.bind('click', function(){
		if (nextFunctions[currentStep]){
			tempFlag = nextFunctions[currentStep]('next');
		}
		
		if (!tempFlag){
			return;
		}
		currentStep ++;
		initFunctions[currentStep]('next');
	});
	
	return nextButton;
}

/**
 * create the next button base on the currentStep, the first step does not need this button
 * 
 * @return nothing
 */
function createBackButton(){
	var tempFlag = true;
	if (0 == currentStep){
		return undefined;
	}
	
	var backButton = createButton('Back');
	backButton.bind('click', function(){
		if (nextFunctions[currentStep]){
			tempFlag = nextFunctions[currentStep]('back');
		}
		
		if (!tempFlag){
			return;
		}
		
		currentStep--;

		initFunctions[currentStep]('back');
	});
	
	return backButton;
}

/**
 * get the input value on discover page
 * 
 * @param envName 
 * 			value's name(discoverEnv's key)
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
 * set the input value on discover page
 * 
 * @param envName
 * 			value's name(discoverEnv's key)
 * @param envValue 
 * 			value
 * @return nothing
 */
function setDiscoverEnv(envName, envValue){
	if (envName){
		discoverEnv[envName] = envValue;
	}
}

/**
 * delete the input value on discover page
 * 
 * @param envName
 * 			value's name(discoverEnv's key)
 * @return nothing
 */
function removeDiscoverEnv(envName){
	if (discoverEnv[envName]){
		delete discoverEnv[envName];
	}
}

/**
 * Expand the noderange into node names.
 * 
 * @param nodeRange  
 * @return node names array
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
		for (var i = parts[0]; i <= parts[1]; i++){
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
	if (2 > begin){
		retArray.push(nodeRange);
		return retArray;
	}
	
	var end = tempArray[1].match(/^(\D+)(\d+)$/);
	if (2 > end){
		retArray.push(nodeRange);
		return retArray;
	}
	
	if (begin[1] != end[1]){
		retArray.push(nodeRange);
		return retArray;
	}
	
	var prefix = begin[1];
	var len = begin[2].length;
	for (var i = begin[2]; i <= end[2]; i++){
		var ts = i.toString();
		if (ts.length < len){
			ts = "000000".substring(0, (len - ts.length)) + ts;
		}
		retArray.push(prefix + ts);
	}
	
	return retArray;
}

/**
 * collect all inputs' value from the page
 * 
 * @return true: this step is correct, can go to the next page
 *         false: this step contains error.
 */
function collectInputValue(){
	$('#discoverContentDiv input[type=text]').each(function(){
		var name = $(this).attr('name');
		var value = $(this).attr('value');
		if ('' != value){
			setDiscoverEnv(name, value);
		}
		else{
			removeDiscoverEnv(name);
		}
	});
	
	return true;
}

/**
 * verify the ip address,
 * 
 * @param 
 * 
 * @return true: for valid IP address
 *         false : for invalid IP address
 */
function verifyIp(ip){
    var reg = /^(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-4])$/;
    return reg.test(ip);
}

/**
 * transfer ip into decimal
 * 
 * @param 
 * 
 * @return decimal type ip address
 */
function ip2Decimal(ip){
    if (!verifyIp(ip)){
        return 0;
    }
    
    var retIp = 0;
    var tempArray = ip.split('.');
    for (var i = 0; i < 4; i++){
        retIp = (retIp << 8) | parseInt(tempArray[i]);
    }
    
    //change the int into unsigned int type
    retIp = retIp >>> 0;
    return retIp;
}
/**
 * calculate the end IP address by start IP and the number of IP range.
 * 
 * @param 
 * 
 * @return
 */
function calcEndIp(ipStart, num){
    var sum = 0;
    var tempNum = Number(num);
    var temp = /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
    var ipArray = temp.exec(ipStart);
    
    ipArray.shift();
    sum = Number(ipArray[3]) + tempNum;
    if (sum <= 254){
        ipArray[3] = sum;
        return (ipArray.join('.'));
    }
    
    ipArray[3] = sum % 254;
    
    sum = Number(ipArray[2]) + parseInt(sum / 254);
    if (sum <= 255){
        ipArray[2] = sum;
        return (ipArray.join('.'));
    }
    
    ipArray[2] = sum % 255;
    
    sum = Number(ipArray[1]) + parseInt(sum / 255);
    if (sum <= 255){
        ipArray[1] = sum;
        return (ipArray.join('.'));
    }
    
    ipArray[1] = sum % 255;
    ipArray[0] = ipArray[0] + parseInt(sum / 255);
    return (ipArray.join('.'));
}
/**
 * Step 1: show the wizard's function 
 *         platform selector(system P or system X)
 * 
 * @return nothing
 */
function initSelectPlatform(){
	var temp = '';
	var type = '';
	$('#discoverContentDiv').empty();
	$('.tooltip').remove();
	temp += '<div style="min-height:360px"><h2>' + steps[currentStep] + '</h2>';
	temp += '<p>This wizard will guide you through the process of defining the naming conventions within' + 
		'your cluster, discovering the hardware on your network, and automatically defining it in the xCAT' +
		'database.<br/>Choose which type of hardware you want to discover, and then click Next.</p>';
	temp += '<input type="radio" name="platform" id="idataplex"><label for="idataplex">iDataPlex</label></input><br/>';
	temp += '<input type="radio" name="platform" disabled="true" id="blade"><span  style="color:gray;"> Blade Center</span></input><br/>';
	temp += '<input type="radio" name="platform" id="ih"> System p hardware (P7 IH)</input><br/>';
	temp += '<input type="radio" name="platform" id="nonih"> System p hardware (Non P7 IH)</input><br/>';
	temp += '</div>';
	$('#discoverContentDiv').append(temp);
	
	if (getDiscoverEnv('machineType')){
		type = getDiscoverEnv('machineType');
	}
	else{
		type = 'ih';
	}
	
	$('#discoverContentDiv #' + type).attr('checked', 'checked');
	createDiscoverButtons();
}

/**
 * Step 1: Get the platform type
 * 
 * @return true
 */
function getPlatform(){
	var radioValue = $('#discoverContentDiv :checked').attr('id');
	var platformObj;
	switch(radioValue){
	    case 'ih':
	    case 'nonih':{
	        platformObj = new hmcPlugin();
	    }
	    break;
	    case 'idataplex':{
	    	platformObj = new ipmiPlugin();
	    }
	    break;
	    case 'blade':{
	        
	    }
	    break;
	}
	steps = ['Platform'].concat(platformObj.getStep(), 'compelte');
	initFunctions = [initSelectPlatform].concat(platformObj.getInitFunction(), complete);
	nextFunctions = [getPlatform].concat(platformObj.getNextFunction(), undefined);
	setDiscoverEnv('machineType', radioValue);
	return true;
}

/**
 * last step: complete
 *          
 * @param 
 * 
 * @return
 */
function complete(){
	$('#discoverContentDiv').empty();
	$('.tooltip').remove();
	var showStr = '<div style="min-height:360px"><h2>' + steps[currentStep] + '<br/><br/></h2>';
	showStr += 'You can go to the <a href="index.php">nodes page</a> to check nodes which were defined just now.';
	$('#discoverContentDiv').append(showStr);
	
	createDiscoverButtons();
}
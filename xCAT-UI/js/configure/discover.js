// Associate the step name with step number
var steps = [ 'Platform', 'Complete' ];

// Associate the function with step number
var initFunctions = [ initSelectPlatform, complete ];
var nextFunctions = [ getPlatform, undefined ];

// Save current step number
var currentStep = 0;

// Save user's input
var discoverEnv;

/**
 * Create the discovery page
 */
function loadDiscoverPage() {
    currentStep = 0;
    discoverEnv = new Object();

    $('#discoverTab').append('<div class="discovercontent" id="discoverContentDiv"><div>');
    initSelectPlatform();
}

/**
 * Create the navigation buttons on the bottom of discovery page
 */
function createDiscoverButtons() {
    var buttonDiv = $('<div style="text-align:center;padding:20px 0px 10px 0px;"></div>');
    var backButton = createBackButton();
    var nextButton = createNextButton();
    var cancelButton = createCancelButton();

    if (backButton)
        buttonDiv.append(backButton);

    if (nextButton)
        buttonDiv.append(nextButton);

    if (cancelButton)
        buttonDiv.append(cancelButton);

    $('#discoverContentDiv').append(buttonDiv);
}

function createCancelButton() {
    if (0 == currentStep)
        return undefined;

    if ((steps.length - 1) == currentStep)
        return undefined;

    var cancelbutton = createButton('Cancel');
    cancelbutton.bind('click', function() {
        $('#discoverTab').empty();
        for (var name in discoverEnv)
            removeDiscoverEnv(name);
        loadDiscoverPage();
    });

    return cancelbutton;
}

/**
 * Create the next button base on the current step, 
 * the last step does not need this button
 */
function createNextButton() {
    var tempFlag = true;
    if ((steps.length - 1) == currentStep)
        return undefined;

    var nextButton = createButton('Next');
    nextButton.bind('click', function() {
        if (nextFunctions[currentStep])
            tempFlag = nextFunctions[currentStep]('next');

        if (!tempFlag)
            return;
        currentStep++;
        initFunctions[currentStep]('next');
    });

    return nextButton;
}

/**
 * Create the next button base on the current step, 
 * the first step does not need this button
 */
function createBackButton() {
    var tempFlag = true;
    if (0 == currentStep)
        return undefined;

    var backButton = createButton('Back');
    backButton.bind('click', function() {
        if (nextFunctions[currentStep])
            tempFlag = nextFunctions[currentStep]('back');

        if (!tempFlag)
            return;

        currentStep--;

        initFunctions[currentStep]('back');
    });

    return backButton;
}

/**
 * Get the input value on discovery page
 * 
 * @param envName Value name (discoverEnv key)
 * @return If there is an associate value, return the value, else return NULL
 */
function getDiscoverEnv(envName) {
    if (discoverEnv[envName])
        return discoverEnv[envName];
    else
        return '';
}

/**
 * Set the input value on discovery page
 * 
 * @param envName Value name (discoverEnv key)
 * @param envValue Value
 */
function setDiscoverEnv(envName, envValue) {
    if (envName)
        discoverEnv[envName] = envValue;
}

/**
 * Delete the input value on discovery page
 * 
 * @param envName Value name (discoverEnv's key)
 */
function removeDiscoverEnv(envName) {
    if (discoverEnv[envName])
        delete discoverEnv[envName];
}

/**
 * Expand the noderange into node names
 * 
 * @param nodeRange Node range
 * @return Array of node names
 */
function expandNR(nodeRange) {
    var retArray = new Array();
    var tempResult;
    if ('' == nodeRange)
        return retArray;

    tempResult = nodeRange.match(/(.*?)\[(.*?)\](.*)/);
    if (null != tempResult) {
        var parts = tempResult[2].split('-');
        if (2 > parts.length)
            return retArray;

        var len = parts[0].length;
        for (var i = parts[0]; i <= parts[1]; i++) {
            var ts = i.toString();
            if (ts.length < len)
                ts = "000000".substring(0, (len - ts.length)) + ts;

            retArray = retArray.concat(expandNR(tempResult[1] + ts
                    + tempResult[3]));
        }
        
        return retArray;
    }

    var tempArray = nodeRange.split('-');
    if (2 > tempArray.length) {
        retArray.push(nodeRange);
        return retArray;
    }

    var begin = tempArray[0].match(/^(\D+)(\d+)$/);
    if (2 > begin) {
        retArray.push(nodeRange);
        return retArray;
    }

    var end = tempArray[1].match(/^(\D+)(\d+)$/);
    if (2 > end) {
        retArray.push(nodeRange);
        return retArray;
    }

    if (begin[1] != end[1]) {
        retArray.push(nodeRange);
        return retArray;
    }

    var prefix = begin[1];
    var len = begin[2].length;
    for (var i = begin[2]; i <= end[2]; i++) {
        var ts = i.toString();
        if (ts.length < len)
            ts = "000000".substring(0, (len - ts.length)) + ts;
        retArray.push(prefix + ts);
    }

    return retArray;
}

/**
 * Collect all input values from the page
 * 
 * @return True if this step is correct and can go to the next page, false if this step contains error
 */
function collectInputValue() {
    $('#discoverContentDiv input[type=text]').each(function() {
        var name = $(this).attr('name');
        var value = $(this).attr('value');
        if ('' != value)
            setDiscoverEnv(name, value);
        else
            removeDiscoverEnv(name);
    });

    return true;
}

/**
 * Verify the IP address
 * 
 * @param ip IP address
 * @return True if IP address is valid, false otherwise
 */
function verifyIp(ip) {
    var reg = /^(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-4])$/;
    return reg.test(ip);
}

/**
 * Transalate IP into decimal
 * 
 * @param ip IP address
 * @return Decimal type for IP address
 */
function ip2Decimal(ip) {
    if (!verifyIp(ip))
        return 0;

    var retIp = 0;
    var tempArray = ip.split('.');
    for (var i = 0; i < 4; i++) {
        retIp = (retIp << 8) | parseInt(tempArray[i]);
    }

    // Change the int into unsigned int type
    retIp = retIp >>> 0;
    return retIp;
}

/**
 * Calculate the ending IP address from the starting IP address and the IP range number.
 */
function calcEndIp(ipStart, num) {
    var sum = 0;
    var tempNum = Number(num);
    var temp = /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
    var ipArray = temp.exec(ipStart);

    ipArray.shift();
    sum = Number(ipArray[3]) + tempNum;
    if (sum <= 254) {
        ipArray[3] = sum;
        return (ipArray.join('.'));
    }

    ipArray[3] = sum % 254;

    sum = Number(ipArray[2]) + parseInt(sum / 254);
    if (sum <= 255) {
        ipArray[2] = sum;
        return (ipArray.join('.'));
    }

    ipArray[2] = sum % 255;

    sum = Number(ipArray[1]) + parseInt(sum / 255);
    if (sum <= 255) {
        ipArray[1] = sum;
        return (ipArray.join('.'));
    }

    ipArray[1] = sum % 255;
    ipArray[0] = ipArray[0] + parseInt(sum / 255);
    return (ipArray.join('.'));
}

/**
 * Step 1: Show the wizard's function platform selector (System p or System x)
 */
function initSelectPlatform() {
    var type = '';

    $('#discoverContentDiv').empty();
    $('.tooltip').remove();

    var selectPlatform = $('<div style="min-height:360px"><h2>' + steps[currentStep] + '</h2></div>');

    var infoMsg = 'This wizard will guide you through the process of defining the naming conventions within'
            + 'your cluster, discovering the hardware on your network, and automatically defining it in the xCAT'
            + 'database. Choose which type of hardware you want to discover, and then click Next.';
    var info = createInfoBar(infoMsg);
    selectPlatform.append(info);

    var hwList = $('<ol>Platforms available:</ol>');
    hwList.append('<li><input type="radio" name="platform" id="idataplex"><label>iDataPlex</label></input></li>');
    hwList.append('<li><input type="radio" name="platform" disabled="true" id="blade"><span  style="color:gray;"> BladeCenter</span></input></li>');
    hwList.append('<li><input type="radio" name="platform" id="ih"> System p hardware (P7 IH)</input></li>');
    hwList.append('<li><input type="radio" name="platform" id="nonih"> System p hardware (Non P7 IH)</input></li>');

    hwList.find('li').css('padding', '2px 10px');
    selectPlatform.append(hwList);

    $('#discoverContentDiv').append(selectPlatform);

    if (getDiscoverEnv('machineType'))
        type = getDiscoverEnv('machineType');
    else
        type = 'ih';

    $('#discoverContentDiv #' + type).attr('checked', 'checked');
    createDiscoverButtons();
}

/**
 * Step 1: Get the platform type
 */
function getPlatform() {
    var radioValue = $('#discoverContentDiv :checked').attr('id');
    var platformObj = null;
    switch (radioValue) {
    case 'ih':
    case 'nonih':
        platformObj = new hmcPlugin();
        break;
    case 'idataplex':
        platformObj = new ipmiPlugin();
        break;
    case 'blade':
        break;
    }

    steps = [ 'Platform' ].concat(platformObj.getStep(), 'compelte');
    initFunctions = [ initSelectPlatform ].concat(platformObj.getInitFunction(), complete);
    nextFunctions = [ getPlatform ].concat(platformObj.getNextFunction(), undefined);
    setDiscoverEnv('machineType', radioValue);
    return true;
}

/**
 * Last step: Complete
 */
function complete() {
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showStr = '<div style="min-height:360px"><h2>' + steps[currentStep] + '<br/><br/></h2>';
    showStr += 'You can go to the <a href="index.php">nodes page</a> to check nodes which were defined just now.';
    $('#discoverContentDiv').append(showStr);

    createDiscoverButtons();
}
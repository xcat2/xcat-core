/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
	// Load utility scripts
});

/**
 * Constructor
 * 
 * @return Nothing
 */
var hmcPlugin = function() {

};

/**
 * Clone node (service page)
 * 
 * @param node
 * 			Node to clone
 * @return Nothing
 */
hmcPlugin.prototype.serviceClone = function(node) {

};

/**
 * Load provision page (service page)
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
hmcPlugin.prototype.loadServiceProvisionPage = function(tabId) {
	
};

/**
 * Show node inventory (service page)
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
hmcPlugin.prototype.loadServiceInventory = function(data) {
	
};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
hmcPlugin.prototype.loadInventory = function(data) {
	// Get arguments
	var args = data.msg.split(',');
	// Get tab ID
	var tabId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get node inventory
	var inv = data.rsp;

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

	// Loop through each line
	var fieldSet, legend, oList, item;
	for (var k = 0; k < inv.length; k++) {
		// Remove node name in front
		var str = inv[k].replace(node + ': ', '');
		str = jQuery.trim(str);

		// If string is a header
		if (str.indexOf('I/O Bus Information') > -1 || str.indexOf('Machine Configuration Info') > -1) {
			// Create a fieldset
			fieldSet = $('<fieldset></fieldset>');
			legend = $('<legend>' + str + '</legend>');
			fieldSet.append(legend);
			oList = $('<ol></ol>');
			fieldSet.append(oList);
			invDiv.append(fieldSet);
		} else {
			// If no fieldset is defined
			if (!fieldSet) {
				// Define general fieldset
				fieldSet = $('<fieldset></fieldset>');
				legend = $('<legend>General</legend>');
				fieldSet.append(legend);
				oList = $('<ol></ol>');
				fieldSet.append(oList);
				invDiv.append(fieldSet);
			}

			// Append the string to a list
			item = $('<li></li>');
			item.append(str);
			oList.append(item);
		}
	}

	// Append to inventory form
	$('#' + tabId).append(invDiv);
};

/**
 * Load clone page
 * 
 * @param node
 *            Source node to clone
 * @return Nothing
 */
hmcPlugin.prototype.loadClonePage = function(node) {
	// Get nodes tab
	var tab = getNodesTab();
	var newTabId = node + 'CloneTab';

	// If there is no existing clone tab
	if (!$('#' + newTabId).length) {
		// Create status bar and hide it
		var statBarId = node + 'CloneStatusBar';
		var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>').hide();

		// Create info bar
		var infoBar = createInfoBar('Under construction');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
		cloneForm.append(statBar);
		cloneForm.append(infoBar);

		// Add clone tab
		tab.add(newTabId, 'Clone', cloneForm, true);
	}

	tab.select(newTabId);
};

/**
 * Load provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
hmcPlugin.prototype.loadProvisionPage = function(tabId) {
    // Create provision form
    var provForm = $('<div class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Provision a node on System p.');
    provForm.append(infoBar);

    // Append to provision tab
    $('#' + tabId).append(provForm);

    /**
     * Create provision new node division
     */
    // You should copy whatever is in this function, put it here, and customize it
    createProvision('hmc', provForm);
};

/**
 * Load resources
 * 
 * @return Nothing
 */
hmcPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'hmcResourceTab';
	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create info bar
	var infoBar = createInfoBar('Under construction');

	// Create resource form
	var resrcForm = $('<div class="form"></div>');
	resrcForm.append(infoBar);

	$('#' + tabId).append(resrcForm);
};

/**
 * Add node range
 * 
 * @return Nothing
 */
hmcPlugin.prototype.addNode = function() {
	var diaDiv = $('<div id="addpnodeDiv" class="form"></div>');
	diaDiv.append('<div><label>Type:</label><select id="pnodetype"><option>HMC</option><option>Scan Node</option></select></div>');
	diaDiv.append('<div id="pnodeeditarea" ></div>');
	
	// Show the dialog
	diaDiv.dialog({
        modal : true,
        width : 400,
        title : 'Add node',
        close : function(){$('#addpnodeDiv').remove();}
	});
	
	// Bind the select change event
	$('#pnodetype').bind('change', function() {
		$('#pnodeeditarea').empty();
		if ('HMC' == $(this).val()) {
			$('#addpnodeDiv').dialog('option', 'width', '400');
			$('#pnodeeditarea').append('<label>Name:</label><input><br/><label>Username:</label><input><br/>' +
		              '<label>Password:</label><input><br/><label>IP Adress:</label><input>');
			
			$('#addpnodeDiv').dialog('option', 'buttons', 
					                 {'Add': function(){addHmcNode();}, 
				                      'Cancel': function(){$('#addpnodeDiv').dialog('close');}});
		} else {
			//add loader image and delete buttons
			$('#pnodeeditarea').append(createLoader());
			$('#addpnodeDiv').dialog('option', 'buttons', {'Cancel': function(){$('#addpnodeDiv').dialog('close');}});
			$('#addpnodeDiv').dialog('option', 'width', '650');
			$.ajax({
				url : 'lib/cmd.php',
		        dataType : 'json',
		        data : {
		            cmd : 'nodels',
		            tgt : 'all',
		            args : 'ppc.nodetype==hmc',
		            msg : ''
		        },
		        success : function(data) {
		        	$('#pnodeeditarea img').remove();
		        	drawHmcSelector(data.rsp);
		        }
			});
		}
	});
	
	// Trigger the select change event
	$('#pnodetype').trigger('change');
};

hmcPlugin.prototype.getStep = function(){
	return ['Basic Patterns',
	        'Supernode',
	        'More patterns',
	        'Power on hardware',
            'Discover frames',
            'Management node',
            'Update definitions',
            'Create LPARs'];
};

hmcPlugin.prototype.getInitFunction = function(){
	return [powerInitBasicPattern,
            powerInitSupernode,
            powerInitSiteTable,
            powerInitPoweronHardware,
            powerInitDiscoverFrames,
            powerInitConfig,
            powerInitUpdateDefinition,
            powerInitCreateLpar];
};

hmcPlugin.prototype.getNextFunction = function(){
	return [checkBasicPattern,
            checkSupernode,
            checkSiteTable,
            undefined,
            checkFrameMtms,
            undefined,
            undefined,
            collectInputValue];
};
/**
 * Add HMCs into the dialog
 * 
 * @param hmc
 * 			HMCs
 * @return Nothing
 */
function drawHmcSelector(hmcs){
	if (1 > hmcs.length) {
		$('#pnodeeditarea').append(createWarnBar('Please define HMC node first.'));
		return;
	}
	
	// Add HMCs into a selector and add a scan button
	var hmcoption = '';
	var scanbutton = createButton('Scan');
	for (var i in hmcs) {
		hmcoption += '<option>' + hmcs[i][0] + '</option>';
	}
	
	$('#pnodeeditarea').append('<label>HMC:</label><select>' + hmcoption + '</select>');
	$('#pnodeeditarea').append(scanbutton);
	
	scanbutton.bind('click', function() {
		var hmcname = $('#pnodeeditarea select').val();
		$('#pnodeeditarea').append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
	        dataType : 'json',
	        data : {
	            cmd : 'rscan',
	            tgt : hmcname,
	            args : '',
	            msg : ''
	        },
	        success : function(data) {
	        	$('#pnodeeditarea img').remove();
	        	
	        	// Draw a table with checkbox
	        	drawRscanResult(data.rsp[0]);
	        	
	        	// Add the add button
	        	$('#addpnodeDiv').dialog('option', 'buttons', 
		                 {'Add': function(){addPNode();}, 
	                      'Cancel': function(){$('#addpnodeDiv').dialog('close');}});
	        }
		});
	});
}

function drawRscanResult(rscanresult){
	var line = '';
	var tempreg = /\S+/g;
	var idpreg = /^\d+$/;
	var resultDiv = $('<div class="tab" style="height:300px;overflow:auto;"></div>');
	var rscantable = $('<table></table>');
	var temprow = '';
	var colnum = 0;
	var fields = 0;
	
	$('#pnodeeditarea div').remove();
	if (!rscanresult) {
		return;
	}
	
	var rows = rscanresult.split("\n");
	if (rows.length < 2) {
		return;
	}
	
	// Add the table header
	fields = rows[0].match(tempreg);
	colnum = fields.length;
	temprow = '<tr><td><input type="checkbox" onclick="selectAllRscanNode(this)"></td>';
	for(var i in fields) {
		temprow += '<td>' + fields[i] + '</td>';
	}
	rscantable.append(temprow);
	
	// Add the tbody
	for (var i = 1; i < rows.length; i++) {
		line = rows[i];
		if (!line) {
			continue;
		}
		
		var fields = line.match(tempreg);
		if ('hmc' == fields[0]) {
			continue;
		}
		
		// May be the 3rd field(id) is empty, so we should add the new 
		if (!idpreg.test(fields[2])){
			fields = [fields[0], fields[1], ''].concat(fields.slice(2));
		}
		temprow = '<tr><td><input type="checkbox" name="' + fields[1] + '"></td>';
		
		for(var j = 0; j < colnum; j++) {
			temprow += '<td>';
			if (fields[j]) {
				if (j == 1){
					temprow += '<input value="' + fields[j] + '">';
				}
				else{
					temprow += fields[j];
				}
			}
			temprow += '</td>';
		}
		temprow += '</tr>';
		rscantable.append(temprow);
	}
	
	resultDiv.append(rscantable);
	$('#pnodeeditarea').append(resultDiv);
}

/**
 * Add hmc node
 * 
 * @return Nothing
 */
function addHmcNode(){
	var errorinfo = '';
	var args = '';
	$('#pnodeeditarea input').each(function(){
		if (!$(this).val()){
			errorinfo = 'Please provide a value for each missing field!';
		}
		args += $(this).val() + ',';
	});
	
	if (errorinfo){
		// Add warning message
		alert(errorinfo);
		return;
	}
	
	// Disabled the button
	$('.ui-dialog-buttonpane button').attr('disabled', 'disabled');
	
	args = args.substr(0, args.length - 1);
	
	$('#pnodeeditarea').append(createLoader());
	// Send the save HMC request
	$.ajax({
		url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;hmc;' + args,
            msg : ''
        },
        success : function(data){
        	// Refresh the area on the right side
        	$('#addpnodeDiv').dialog('close');
        	$('.selectgroup').trigger('click');
        }
	});
}

/**
 * Add System p node, contains frame, cec, lpar 
 * 
 * @return Nothing
 */
function addPNode(){
	// Get the HMC name
	var hmcname = $('#pnodeeditarea select').val();
	var nodename = '';
	// Get checked nodes
	$('#pnodeeditarea :checked').each(function() {
		if ($(this).attr('name')) {
			nodename += $(this).attr('name') + ',';
			nodename += $(this).parents('tr').find('input').eq(1).val() + ',';
		}
	});
	
	if (!nodename) {
		alert('You should select nodes first!');
		return;
	}
	
	// Disabled the button
	$('.ui-dialog-buttonpane button').attr('disabled', 'disabled');
	
	nodename = nodename.substr(0, nodename.length - 1);
	$('#pnodeeditarea').append(createLoader());
	// Send the add request
	$.ajax({
		url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;node;' + hmcname + ',' + nodename,
            msg : ''
        },
        success : function(data) {
        	// Refresh the area on the right side
        	$('#addpnodeDiv').dialog('close');
        	$('.selectgroup').trigger('click');
        }
	});
}

/**
 * Select all checkbox in a table 
 * 
 * @return Nothing
 */
function selectAllRscanNode(obj){
	var status = $(obj).attr('checked');
	$(obj).parents('table').find(':checkbox').attr('checked', status);
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
function powerInitBasicPattern(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showString = '<div style="min-height:360px" id="patternDiv"><h2>' + steps[currentStep] + '</h2>';
    showString += '<table><tbody>';
    //Frame title
    showString += '<tr><td><h3>Frames:</h3></td></tr>';
    //Frame Name
    showString += '<tr><td>Name Range:</td><td><input type="text" title="Format: Frame[1-6] or F1-F6" ' +
                  'name="frameName" value="' + getDiscoverEnv('frameName') + '"></td>';
    //use the super node configure file to calculate the cec's number
    showString += '<td></td><td></td></tr>';

    //CEC title
    showString += '<tr><td><h3>Drawers:</h3></td></tr>';
    //CEC name
    showString += '<tr><td>Name Range:</td><td><input type="text" title="Format: CEC[1-60] or F[1-6]C[1-10]" ' +
                  'name="cecName" value="' + getDiscoverEnv('cecName') + '"></td>';
    //Number of LPARs per Drawer:
    showString += '<td>Number of LPARs per Drawer:</td><td><input type="text" name="lparNumPerCec" value="' + 
                  getDiscoverEnv('lparNumPerCec') + '"></td></tr>';

    //Lpar title
    showString += '<tr><td><h3>Lpars:</h3></td></tr>';
    //lpar name
    showString += '<tr><td>Name Range:</td><td><input type="text" title="Format: F[1-6]C[1-10]L[1-8]" ' + 
                  'name="lparName" value="' + getDiscoverEnv('lparName') + '"></td><td></td><td></td></tr>';
    
    //hmc title
    showString += '<tr><td><h3>HMCs:</h3></td></tr>';
    //hmc name
    showString += '<tr id="hmcTr"><td>Name Range:</td><td><input type="text" title="Format: HMC[01-10] or HMC01-HMC10" name="hmcName" value="' + getDiscoverEnv('hmcName') + '"></td>';
    //Number of Frames per HMC
    showString += '<td>Number of Frames per HMC:</td><td><input type="text" name="frameNumPerHmc" value="' + 
                  getDiscoverEnv('frameNumPerHmc') + '"></td></tr>';
    showString += '<tr><td>Hardware Managment:</td><td><input type="radio" name="managetype" value="hmc" title="Hardware Management Console">HMC&nbsp;&nbsp;';
    showString += '<input type="radio" name="managetype" value="dfm" title="Direct FSP Management">DFM</td></tr>';
    showString += '</tbody></table></div>';
    
    $('#discoverContentDiv').append(showString);
    
    $('#discoverContentDiv [title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 1
    });
    
    //change the radio inputs' checked status
    if (getDiscoverEnv('hmcFlag')){
        $('#discoverContentDiv :radio[value=hmc]').attr('checked', 'checked');
    }
    else{
        $('#discoverContentDiv :radio[value=dfm]').attr('checked', 'checked');
    }
    
    createDiscoverButtons();
}

/**
 * Step 2: check basic patterns 
 *          when user input the basic patterns, we should check if the input is correct. 
 * @param 
 * 
 * @return
 */
function checkBasicPattern(operType){
    collectInputValue();

    //click back button, do not need check, only collect input value is ok.
    if ('back' == operType){
        return true;
    }
    
    $('#patternDiv .ui-state-error').remove();
    
    var errMessage = '';
    var tempName = '';
    var frameNum = 0;
    var cecNum = 0;
    var lparNum = 0;
    var hmcNum = 0;
    var cecNumPerFrame = getDiscoverEnv('cecNumPerFrame');
    var frameNumPerHmc = getDiscoverEnv('frameNumPerHmc');
    var lparNumPerCec = getDiscoverEnv('lparNumPerCec');
    
    //check the frame name
    tempName = getDiscoverEnv('frameName');
    if (!tempName){
        errMessage += 'Input the Frame Name Range.<br/>';
    }
    else{
        frameNum = expandNR(tempName).length;
    }
    
    //check the cec name
    tempName = getDiscoverEnv('cecName');
    if (!tempName){
        errMessage += 'Input the CEC Name Range.<br/>';
    }
    else{
        cecNum = expandNR(tempName).length;
    }
    
    //lpar number per cec
    if (!lparNumPerCec){
        errMessage += 'Input the Lpar Number Per Drawer.<br/>';
    }
    
    //check the lpar name
    tempName = getDiscoverEnv('lparName');
    if (!tempName){
        errMessage += 'Input the Lpar Name Range.<br/>';
    }
    else{
        lparNum = expandNR(tempName).length;
    }
    
    //check the hmc name 
    tempName = getDiscoverEnv('hmcName');
    if (!tempName){
        errMessage += 'Input the HMC Name Range.<br/>';
    }
    else{
        hmcNum = expandNR(tempName).length;
    }
    
    //frame number per hmc
    if (!frameNumPerHmc){
        errMessage += 'Input the Frame Number Per HMC.<br/>';
    }
    
    //the hardware management type is hmc.
    if ('hmc' == $('#discoverContentDiv :checked').attr('value')){
        setDiscoverEnv('hmcFlag', true);
    }
    else{
        removeDiscoverEnv('hmcFlag');
    }
    
    //the input value check is finished.
    if ('' != errMessage){
        var warnBar = createWarnBar(errMessage);
        $('#patternDiv').prepend(warnBar);
        return false;
    }
    
    //check the connections between all numbers.
    if (getDiscoverEnv('hmcFlag')){
        if ((Number(frameNumPerHmc) * hmcNum) < frameNum){
            errMessage += 'The frame number should less than ' + Number(cecNumPerFrame) * frameNum + 
            ' ("the number of hmc" * "the number of frame managed by per hmc")';
        }
    }
    
    if ((Number(lparNumPerCec) * cecNum) != lparNum){
        errMessage += 'The number of Lpars calculate by Name Range should be ' + Number(lparNumPerCec) * cecNum +
                      '("the number of Drawers" * "the number of lpar per drawer")';
    }
    
    if ('' != errMessage){
        var warnBar = createWarnBar(errMessage);
        $('#patternDiv').prepend(warnBar);
        return false;
    }
    
    setDiscoverEnv('cecNum', cecNum);
    setDiscoverEnv('frameNum', frameNum);
    setDiscoverEnv('lparNum', lparNum);
    setDiscoverEnv('hmcNum', hmcNum);
    return true;
}

/**
 * Step 3: allowed the users to edit the super node condigure file 
 *          
 * @param 
 * 
 * @return
 */
function powerInitSupernode(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    $('#discoverContentDiv').append('<div style="min-height:360px" id="supernodeDiv"><h2>' + steps[currentStep] + '</h2></div>');
    createDiscoverButtons();
    
    //add the introduction about the page
    var infoStr = '<div>The supernode-list file lists what supernode numbers should be ';
    infoStr += 'given to each CEC in each frame. Here is a sample file:<br/>';
    infoStr += 'frame1: 0, 1, 16<br/>frame2: 17, 32<br/>frame3: 33, 48, 49<br/>';
    infoStr += 'frame4: 64 , 65, 80<br/>frame5: 81, 96<br/>frame6: 97(1), 112(1), 113(1), 37(1), 55, 71<br/>';
    infoStr += 'The name before the colon is the node name of the frame BPC. The numbers after the colon ' +
               'are the supernode numbers to assign to the groups of CECs in that frame from bottom to top. ' +
               'Each supernode contains 4 CECs, unless it is immediately followed by "(#)", in which case the ' +
               'number in parenthesis indicates how many CECs are in this supernode.</div>';
    var InfoBar = createInfoBar(infoStr);
    $('#discoverContentDiv #supernodeDiv').append(InfoBar);
    
    var frameArray = expandNR(getDiscoverEnv('frameName'));
    var showStr = '<center><table><tbody>';
    for (var i in frameArray){
        showStr += '<tr><td>' + frameArray[i] + ':</td><td><input type="text" name="sp_' + frameArray[i] + 
                   '" value="' + getDiscoverEnv('sp_' + frameArray[i]) + '"></td></tr>';
    }
    showStr += '</tbody></table></center>';
    $('#discoverContentDiv #supernodeDiv').append(showStr);
}

/**
 * Step 3: check the super node configure file 
 *          
 * @param 
 * 
 * @return
 */
function checkSupernode(operType){
    collectInputValue();
    
    if ('back' == operType){
        return true;
    }
    
    $('#supernodeDiv .ui-state-error').remove();
    
    var errString = '';
    var eceNum = 0;
    var args = '';
    var frameArray = expandNR(getDiscoverEnv('frameName'));
    for (var i in frameArray){
        var sp_config = getDiscoverEnv('sp_' + frameArray[i]);
        if (sp_config){
            eceNum += calcCec(sp_config);
            if (0 == i){
                args += frameArray[i] + ': ' + sp_config;
            }
            else{
                args += '\n' + frameArray[i] + ': ' + sp_config;
            }
        }
        else{
            errString += 'Input the super node configure for ' + frameArray[i] + '<br/>';
        }
    }
    
    args += '\n';
    
    var warnBar;
    if (errString){
        warnBar = createWarnBar(errString);
        $('#supernodeDiv').prepend(warnBar);
        return false;
    }
    
    var cecArray = expandNR(getDiscoverEnv('cecName'));
    if (eceNum != cecArray.length){
        errString += 'The number of CEC calculated from supernode configure is ' + eceNum + ', but the number ' + 
                     'calculated from CECs\' Name Range is ' + cecArray.length + '. Reconfigure the supernode please.';
        warnBar = createWarnBar(errString);
        $('#supernodeDiv').prepend(warnBar);
        return false;
    }
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'writeconfigfile;/tmp/websupernode.txt;' + args,
            msg : ''
        }
    });
    
    return true;
}

function calcCec(spConfigStr){
    var tempArray = spConfigStr.split(',');
    var num = 0;
    var reg = /\(([1-4])\)/;
    for (var i in tempArray){
        var regRes = reg.exec(tempArray[i]);
        if (regRes && regRes[1]){
            num += Number(regRes[1]);
        }
        else{
            num += 4;
        }
    }
    
    return num;
}

/**
 * Step 4: show the field which need to be configured in site table 
 *          
 * @param 
 * 
 * @return
 */
function powerInitSiteTable(operType){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showDiv = $('<div style="min-height:360px" id="siteDiv"><h2>' + steps[currentStep] + '(Site info)</h2></div>');
    var statBar = createStatusBar('siteTableStat');
    statBar.find('div').append(createLoader());
    showDiv.append(statBar);
    $('#discoverContentDiv').append(showDiv);
    
    if (getDiscoverEnv('domainname')){
        showSiteArea();
        return;
    }
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'site',
            msg : ''
        },
        
        success : function(data){
            setDiscoverEnv('domainname', '');
            setDiscoverEnv('nameserver','');
            for (var i in data.rsp){
                var tempArray = data.rsp[i].split(',');
                var tempValue = tempArray[1];
                switch (tempArray[0]){
                    case '"domain"':{
                        setDiscoverEnv('domainname', tempValue.substr(1, tempValue.length - 2));
                    }
                    break;
                    case '"nameservers"':{
                        setDiscoverEnv('nameserver', tempValue.substr(1, tempValue.length - 2));
                    }
                    break;
                }
            }

            showSiteArea();
        }
    }); 
}

/**
 * Step 4: when the values are ready, create the table 
 *          
 * @param 
 * 
 * @return
 */
function showSiteArea(){
    var showString = '<table><tbody>';
    //domain name:
    showString += '<tr><td>Domain Name:</td><td><input type="text" name="domainname" value="' + getDiscoverEnv('domainname') + 
                  '" title="The DNS domain name used for the cluster."></td></tr>';

    //Name server
    showString += '<tr><td>Name server:</td><td><input type="text" name="nameserver" value="' + getDiscoverEnv('nameserver') + 
                  '" title="A comma delimited list of DNS servers that each node in the cluster should use - often the xCAT management node."></td></tr>';
    
    //ntp server
    showString += '<tr><td>DHCP Dynamic Range:</td><td><input type="text" name="ipStart" value="' + getDiscoverEnv('ipStart') + 
                  '" title="A start Ip address for DHCP dynamic range.">-<input type="text" name="ipEnd" disabled="disabled" value="' + 
                  getDiscoverEnv('ipEnd') + '"></td></tr>';
    showString += '</tbody></table>';
    
    $('#discoverContentDiv div').eq(0).append(showString);
    
    $('#discoverContentDiv [title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 1
    });
    
    $('#discoverContentDiv input[name=ipStart]').bind('change', function(){
        if (verifyIp($(this).attr('value'))){
            var tempNum = Number(getDiscoverEnv('frameNum')) * 4 + Number(getDiscoverEnv('cecNum')) * 4 +
                          Number(getDiscoverEnv('lparNum')) + Number(getDiscoverEnv('hmcNum'));
            var ipEnd = calcEndIp($(this).attr('value'), tempNum);
            if (!verifyIp(ipEnd)){
                ipEnd = '';
            }
            $('#discoverContentDiv input[name=ipEnd]').attr('value', ipEnd);
        }
        else{
            $('#discoverContentDiv input[name=ipEnd]').attr('value', '');
        }
    });
    
    //show the current network interface configure
    $.ajax({
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'ifconfig | grep -E "encap|Mask"'
        },
    
        success : function(data){
            $('#discoverContentDiv #siteTableStat div').html('Current network interface configuration:<br/><pre>' + 
                        data.rsp + '</pre>');
        }
    });
    createDiscoverButtons();
}

/**
 * Step 4: check the input are all filled 
 *          
 * @param 
 * 
 * @return
 */
function checkSiteTable(operType){
    $('#discoverContentDiv input[name=ipStart]').trigger('change');
    collectInputValue();
    
    if ('back' == operType){
        return true;
    }
    
    $('#discoverContentDiv .ui-state-error').remove();
    var errMessage = '';
    if (!getDiscoverEnv('domainname')){
        errMessage += 'Input the domain name.<br/>';
    }
    
    if (!getDiscoverEnv('nameserver')){
        errMessage += 'Input the name server.<br/>';
    }
    
    if (!getDiscoverEnv('ipEnd')){
        errMessage += 'Input the DHCP Dynamic Range.<br/>';
    }
    
    if ('' == errMessage){
    	//update the dynamic ip to xcat db by xcatsetup and run makedhcp
    	$.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'dynamiciprange;' + getDiscoverEnv('ipStart') + '-' + getDiscoverEnv('ipEnd'),
                msg : ''
            }
    	});
        return true;
    }
    
    var warnBar = createWarnBar(errMessage);
    $('#discoverContentDiv #siteDiv').prepend(warnBar);
    return false;
}

/**
 * Step 5: told users to power on machines
 *          
 * @param 
 * 
 * @return
 */
function powerInitPoweronHardware(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showStr = '<div style="min-height:360px"><h2>' + steps[currentStep] + 
            '</h2><h3>Do the following manual steps now:</h3>';
    showStr += '<ul><li>1. Power on the HMCs.</li>';
    showStr += '<li>2. Configure the HMC\'s static IP and enable the SLP & SSH ports by HMC GUI</li>';
    showStr += '<li>3. Power on all of Frames.</li>';
    showStr += '<li>4. Click Next to discover the hardware on the service network.</li></ul></div>';
    
    $('#discoverContentDiv').append(showStr);
    
    createDiscoverButtons();
}

/**
 * Step 6: discover all frames from the cluster and map all mtms with frame name
 *          
 * @param 
 * 
 * @return
 */
function powerInitDiscoverFrames(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showDiv = $('<div style="min-height:360px" id="discoverShow"><h2>' + steps[currentStep] + '</h2>');
    var statBar = createStatusBar('framedisc');
    showDiv.append(statBar);
    $('#discoverContentDiv').append(showDiv);
    $('#discoverShow').append('<center><table><tr><td id="frameTd">' 
            + '</td><td style="width:20px"></td><td id="mtmsTd"></td></tr></table></center>');
    
    if (getDiscoverEnv('framemtmsmap')){
        $('#framedisc div').html('Mapping the frame name and mtms which discovered by lsslp.<br\>' + 
                             'Select the frame name, then select the mtms.');
        var mapArray = getDiscoverEnv('framemtmsmap').split(':');
        for(var i in mapArray){
            var tempArray = mapArray[i].split(',');
            showMap(tempArray[0], tempArray[1] + '-' + tempArray[2]);
        }
        
        createDiscoverButtons();
        return;
    }
    
    statBar.find('div').append('Discovering all Frames by lsslp.').append(createLoader());
    //use lsslp to find all bpas in cluster
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'discover;frame',
            msg : ''
        },
        
        success : function(data){
            var tempInfo = data.rsp[0];
            if (-1 != tempInfo.indexOf('Error')){
                $('#framedisc div').html(tempInfo);
                createDiscoverButtons();
                return;
            }
            
            var mtmsArray = tempInfo.split(';');
            var frameArray = expandNR(getDiscoverEnv('frameName'));
            //chech the defined number and discovered number
            if (mtmsArray.length != frameArray.length){
                $('#framedisc div').html('Error: Definded Number is ' + frameArray.length + 
                                    ', but lsslp discovered Number is ' + mtmsArray.length + ', please check your configure!');
                createDiscoverButtons();
                return;
            }
            
            $('#framedisc div').html('Mapping the frame name and mtms which discovered by lsslp.<br\>' + 
                    'Select the frame name, then select the mtms.');
            
            for (var i in frameArray){
                $('#frameTd').append('<p><input name="frameradio" type="radio" onclick="createMap(this)"><span>' +
                        frameArray[i] + '</span></p>');
                
            }
            
            for (var i in mtmsArray){
                $('#mtmsTd').append('<p><input name="mtmsradio" type="radio" onclick="createMap(this)"><span>' + 
                        mtmsArray[i] + '</span></p>');
            }
            
            createDiscoverButtons();
        }
    });
}

function createMap(obj){
    var fname = '';
    var mname = '';
    
    if ($('#discoverShow :checked').size() < 2){
        return;
    }
    
    if('frameradio' == $(obj).attr('name')){
        fname = $(obj).next().html();
        mname = $('#discoverShow input[name=mtmsradio]:checked').next().html();
    }
    else{
        fname = $('#discoverShow input[name=frameradio]:checked').next().html();
        mname = $(obj).next().html();
    }
    
    $('#discoverShow :checked').parent().remove();
    showMap(fname, mname);
}

function showMap(fname, mname){
    var rowClass = '';
    
    if ($('#discoverShow fieldset').size() < 1){
        $('#discoverShow').append('<fieldset><legend>Frame and MTMS map</legend><center><table></table></center></fieldset>');
    }
    
    if (0 == $('#discoverShow fieldset tr').size() % 2){
        rowClass = 'odd';
    }
    else{
        rowClass = 'even';
    }
    
    $('#discoverShow fieldset table').append('<tr class="' + rowClass + '"><td>' + fname + 
            '</td><td width="20px">&lt;----&gt;</td><td>' + mname +
            '</td><td><span class="ui-icon ui-icon-trash" style="cursor:pointer;" onclick="deleteMap(this)"></span></td></tr>');
}

function deleteMap(obj){
    var mname = $(obj).parent().prev().html();
    var fname = $(obj).parent().prev().prev().prev().html();
    
    $(obj).parent().parent().remove();
    
    $('#frameTd').append('<p><input name="frameradio" type="radio" onclick="createMap(this)"><span>' + fname + '</span></p>');
    $('#mtmsTd').append('<p><input name="mtmsradio" type="radio" onclick="createMap(this)"><span>' + mname + '</span></p>');
}

/**
 * Step 6: write the frame and mtms map file
 *          
 * @param 
 * 
 * @return
 */
function checkFrameMtms(operType){
    //check the number of radio button
    var vpdFileCon = '';
    $('#discoverShow .ui-state-error').remove();
    if (0 < $('#discoverShow :radio').size()){
        var warnBar = createWarnBar('Map all of the frame with mtms.');
        $('#discoverContentDiv #discoverShow').prepend(warnBar);
        return false;
    }
    
    //find out all maps
    var maps = '';
    $('#discoverShow fieldset tr').each(function(){
        var fname = $(this).children().eq(0).html();
        var mtms = $(this).children().eq(2).html();
        var pos = mtms.lastIndexOf('-');

        maps += (fname + ',' + mtms.substring(0, pos) + ',' + mtms.substring(pos + 1) + ':');
        vpdFileCon += fname + ':\n';
        vpdFileCon += '  objtype=node\n  serial=' + mtms.substring(pos + 1) + '\n';
        vpdFileCon += '  mtm=' + mtms.substring(0, pos) + '\n  side=A\n';
    });
    
    maps = maps.substr(0, maps.length - 1);
    setDiscoverEnv('framemtmsmap', maps);
    
    if ('back' == operType){
        return true;
    }
    
    //write the maps into vpd table
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'writeconfigfile;/tmp/webvpd.stanza;' + vpdFileCon,
            msg : ''
        }
    });
    
    return true;
}

/**
 * Step 7: create the xcatsetup configure file and run xcatsetup to define all objects 
 *         in xcat database.   
 *          
 * @param 
 * 
 * @return
 */
function powerInitConfig(operType){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showStr = '<div style="min-height:360px"><h2>' + steps[currentStep] + '<br/><br/></h2>';
    var iconClass = '';
    if ('back' == operType){
        iconClass = 'ui-icon-check';
    }
    else{
        iconClass = 'ui-icon-gear';
    }
    showStr += '<ul>';
    showStr += '<li id="fileLine"><span class="ui-icon ' + iconClass + '"></span>Create configure file for xcatsetup.</li>';
    showStr += '<li id="setupLine"><span class="ui-icon ' + iconClass + '"></span>Wrote Objects into xCAT database by xcatsetup.</li>';
    showStr += '<li id="dhcpLine"><span class="ui-icon ' + iconClass + '"></span>Configured DHCP.</li>';
    showStr += '</ul></div>';
    
    $('#discoverContentDiv').append(showStr);
    
    if ('back' == operType){
        createDiscoverButtons();
        return;
    }
    
    createSetupFile();
}
/**
 * Step 7: create the xcat configure file
 *          
 * @param 
 * 
 * @return
 */
function createSetupFile(){
    var fileContent = '';
    
    $('#fileLine').append(createLoader());
    //site info
    fileContent += 'xcat-site:\n';
    fileContent += '  domain = ' + getDiscoverEnv('domainname') + '\n';
    if (getDiscoverEnv('hmcFlag')){
        //do nothing
    }
    else{
        fileContent += '  use-direct-fsp-control = 1\n';
    }
    
    //dhcp ip range
    fileContent += 'xcat-service-lan:\n';
    fileContent += '  dhcp-dynamic-range = ' + getDiscoverEnv('ipStart') + '-' + getDiscoverEnv('ipEnd') + '\n';
    
    //hmc
    if (getDiscoverEnv('hmcName')){
        fileContent += 'xcat-hmcs:\n';
        fileContent += '  hostname-range = ' + getDiscoverEnv('hmcName') + '\n';
    }
    
    //frame
    fileContent += 'xcat-frames:\n';
    fileContent += '  hostname-range = ' + getDiscoverEnv('frameName') + '\n';
    fileContent += '  num-frames-per-hmc = ' + getDiscoverEnv('frameNumPerHmc') + '\n';
    fileContent += '  vpd-file = /tmp/webvpd.stanza\n';
    
    //cec
    fileContent += 'xcat-cecs:\n';
    fileContent += '  hostname-range = ' + getDiscoverEnv('cecName') + '\n';
    fileContent += '  delete-unused-cecs = 1\n';
    fileContent += '  supernode-list = /tmp/websupernode.txt\n';
    
    //lpar
    fileContent += 'xcat-lpars:\n';
    fileContent += '  num-lpars-per-cec = ' + getDiscoverEnv('lparNumPerCec') + '\n';
    fileContent += '  hostname-range = ' + getDiscoverEnv('lparName') + '\n';
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'writeconfigfile;/tmp/webxcat.conf;' + fileContent,
            msg : ''
        },
        
        success : function(){
            $('#fileLine img').remove();
            var tempSpan = $('#fileLine').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            runSetup();
        }
    });
}

/**
 * Step 7: run the xcatsetup command
 *          
 * @param 
 * 
 * @return
 */
function runSetup(){
    $('#setupLine').append(createLoader());
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'xcatsetup',
            tgt : '',
            args : '/tmp/webxcat.conf',
            msg : ''
        },
        
        success : function(){
            $('#setupLine img').remove();
            var tempSpan = $('#setupLine').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            configDHCP();
        }
    });
}
/**
 * Step 7: create the dhcp configure file
 *          
 * @param 
 * 
 * @return
 */
function configDHCP(){
    $('#dhcpLine').append(createLoader());
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'makedhcp',
            tgt : '',
            args : '-n',
            msg : ''
        },
        
        success : function(){
            $('#dhcpLine img').remove();
            var tempSpan = $('#dhcpLine').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            createDiscoverButtons();
        }
    });
}

/**
 * Step 8: discover all hmc,cec in cluster and update into xcat database
 *          
 * @param 
 * 
 * @return
 */
function powerInitUpdateDefinition(operType){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showStr = '<div style="min-height:360px"><h2>' + steps[currentStep] + '<br/><br/></h2>';
    showStr += '<ul>';
    showStr += '<li id="frameLine"><span class="ui-icon ui-icon-gear"></span>Update Frames into xCAT database.</li>';
    showStr += '<li id="hmcLine1"><span class="ui-icon ui-icon-gear"></span>Discover HMCs.</li>';
    showStr += '<li id="hmcLine2"><span class="ui-icon ui-icon-gear"></span>Update HMCs into xCAT database.</li>';
    showStr += '<li id="cecLine"><span class="ui-icon ui-icon-gear"></span>Discover CECs and update into xCAT database.</li>';
    showStr += '</ul></div>';
    
    $('#discoverContentDiv').append(showStr);
    
    if ('back' == operType){
        createDiscoverButtons();
        return;
    }
    
    lsslpWriteFrame();
}

/**
 * Step 8: write all the lsslp -s FRAME info into database
 *          
 * @param 
 * 
 * @return
 */
function lsslpWriteFrame(){
    $('#frameLine').append(createLoader());
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsslp',
            tgt : '',
            args : '-s;FRAME;-w',
            msg : ''
        },
        
        success : function(){
            $('#frameLine img').remove();
            var tempSpan = $('#frameLine').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            lsslpWriteHMC();
        }
    });
}

/**
 * Step 8: write all the lsslp -s HMC info into database
 *          
 * @param 
 * 
 * @return
 */
function lsslpWriteHMC(){
    $('#hmcLine1').append(createLoader());
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'discover;hmc',
            msg : ''
        },
        
        success : function(data){
            //modify the page elements
            $('#hmcLine1 img').remove();
            var tempSpan = $('#hmcLine1').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            $('#hmcLine2').append(createLoader());
            
            var hmcArray = expandNR(getDiscoverEnv('hmcName'));
            var mtmsArray = data.rsp[0].split(';');
            var tempPar = '';
            
            if (hmcArray.length != mtmsArray.length){
                //error info
                $('#hmcLine2 img').remove();
                var warnBar = createWarnBar('Error: Defined ' + hmcArray.length  + ' HMCs, but discovered ' + mtmsArray.length + 
                    ' HMCs. Please check the configuration.');
                $('#discoverContentDiv div').prepend(warnBar);
                createDiscoverButtons();
                return;
            }
            
            //create the hmc and mtms pair string
            for (var i in hmcArray){
                var tPos = mtmsArray[i].lastIndexOf('-');
                if ('' == tempPar){
                    tempPar += hmcArray[i] + ',' + mtmsArray[i].substring(0, tPos) + ',' +mtmsArray[i].substring(tPos + 1);
                }
                else{
                    tempPar += ':' + hmcArray[i] + ',' + mtmsArray[i].substring(0, tPos) + ',' +mtmsArray[i].substring(tPos + 1);
                }
            }
            
            //write the mtms and hmcname pair into vpd table
            $.ajax({
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : 'updatevpd;' + tempPar,
                    msg : ''
                },
                success: function(){
                    //run lsslp and write all infomation into datatable
                    $.ajax({
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'lsslp',
                            tgt : '',
                            args : '-s;HMC;-w',
                            msg : ''
                        },
                        success: function(){
                            $('#hmcLine2 img').remove();
                            var tempSpan = $('#hmcLine2').find('span');
                            tempSpan.removeClass('ui-icon-gear');
                            tempSpan.addClass('ui-icon-check');
                            lsslpWriteCec();
                        }
                });
                }
        });
        }
    });
}

/**
 * Step 8: write all the lsslp -s cec info into database
 *          
 * @param 
 * 
 * @return
 */
function lsslpWriteCec(){
    $('#cecLine').append(createLoader());
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsslp',
            tgt : '',
            args : '-s;CEC;-w',
            msg : ''
        },
        success: function(){
            $('#cecLine img').remove();
            var tempSpan = $('#cecLine').find('span');
            tempSpan.removeClass('ui-icon-gear');
            tempSpan.addClass('ui-icon-check');
            createDiscoverButtons();
        }
    });
}

/**
 * Step 9: create lpars
 *          
 * @param 
 * 
 * @return
 */
function powerInitCreateLpar(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showDiv = $('<div style="min-height:360px" id="createlparDiv"><h2>' + steps[currentStep] + '</h2>');
    switch (getDiscoverEnv('machineType')){
        case 'ih':{
            ihCreateLpar(showDiv);
        }
        break;
        case 'nonih':{
            nonihCreateLpar(showDiv);
        }
        break;
        default:
        break;
    }
    $('#discoverContentDiv').append(showDiv);
    createDiscoverButtons();
}

function ihCreateLpar(parentDiv){
    var showStr = 'Partition Rule:<br/>' + 
        'If all the octants configuration value are same in one CEC,  it will be  " -r  0-7:value".<br/>' +
        'If the octants use the different configuration value in one cec, it will be "-r 0:value1,1:value2,...7:value7", or "-r 0:value1,1-7:value2".<br/>' +
        'The octants configuration value for one Octant could be  1, 2, 3, 4, 5 . The meanings of the octants configuration value  are as following:<br/>' +
        '1 - 1 partition with all cpus and memory of the octant<br/>' +
        '2 - 2 partitions with a 50/50 split of cpus and memory<br/>' +
        '3 - 3 partitions with a 25/25/50 split of cpus and memory<br/>' +
        '4 - 4 partitions with a 25/25/25/25 split of cpus and memory<br/>' +
        '5 - 2 partitions with a 25/75 split of cpus and memory<br/>' +
        'Define the configuration rule for one CEC, and create all Lpars on all CECs by this rule. Or ignore this step.';
    
    parentDiv.append(createInfoBar(showStr));
    parentDiv.append('<div><center><table><tr><td>Partition Configuration:</td>' +
                     '<td><input name="partconf" type="text" value="' + getDiscoverEnv('partconf')+ 
                     '"></td><td></td></tr></table></center></div>');
    
    var lparButton = createButton('Create Lpars');
    parentDiv.find('td').eq(2).append(lparButton);
    
    lparButton.bind('click', function(){
        var reg = /(([0-7]|[0-7]-[0-7]):[1-5],)*(([0-7]|[0-7]-[0-7]):[1-5])$/g;
        var lparCount = 0;
        $('#discoverContentDiv .ui-state-error').remove();
        collectInputValue();
        var inputStr = getDiscoverEnv('partconf');
        var testArray = reg.exec(inputStr);
        if (!testArray || inputStr != testArray[0]){
            var warnBar = createWarnBar('Input the correct configuration rule.');
            $('#discoverContentDiv').prepend(warnBar);
            return;
        }

        var ruleArray = inputStr.split(',');
        for (var i in ruleArray){
            var octantCount = 0;
            var octantArray = ruleArray[i].split(':');
            var octantRule = Number(octantArray[1]);
            var pos = octantArray[0].indexOf('-');
            if (5 == octantRule){
                octantRule = 2;
            }

            if (-1 == pos){
                octantCount = 1;
            }
            else{
                var startIndex = Number(octantArray[0].substring(0, pos));
                var endIndex = Number(octantArray[0].substring(pos + 1));
                octantCount = endIndex - startIndex + 1;
            }
            
            lparCount += octantCount * octantRule;
        }
        
        if (getDiscoverEnv('lparNumPerCec') != lparCount){
            var warnBar = createWarnBar('The LPAR number per CEC is ' + getDiscoverEnv('lparNumPerCec') + ', but the configuration ' +
                'rule calculation is ' + lparCount + '.');
            $('#discoverContentDiv').prepend(warnBar);
            return;
        }
        
        var diaDiv = $('<div id="createLparDiv"></div>');
        diaDiv.append('<ul></ul>');
        diaDiv.append(createLoader());
        diaDiv.dialog({
            modal: true,
            width: 600,
            title: 'Creating Lpars...'
        });
        
        $('.ui-dialog-titlebar-close').hide();
        
        var cecArray = expandNR(getDiscoverEnv('cecName'));
        for (var i in cecArray){
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'mkvm',
                    tgt : cecArray[i] + 'nodes',
                    args : '-i;1;-m;non-interleaved;-r;' + inputStr,
                    msg : cecArray[i] + ';' + cecArray.length
                },

                success : function(data) {
                    //update the dialogure
                    var tempArray = data.msg.split(';');
                    updateCreateLparDia(tempArray[0], Number(tempArray[1]));
                }
            });
        }
    });
}

function updateCreateLparDia(cecname, cecNum){
    $('#createLparDiv ul').append('<li>Creating lpars on ' + cecname + ' competed.</li>');
    
    if (cecNum != $('#createLparDiv li').size()){
        return;
    }
    
    $('#createLparDiv').empty();
    $('#createLparDiv').append('<p>All lpars are created. You must:<br/>1. reboot the all CECS. <br/>'+
                               '2.use chvm to assign the I/O slots to the new LPAR.</p>');
    
    var chvmButton = createButton('OK');
    $('#createLparDiv').append(chvmButton);
    chvmButton.bind('click', function(){
        $('#createLparDiv').dialog('destroy');
        $('#createLparDiv').remove();
    });
}

function nonihCreateLpar(parentDiv){
    var showStr = 'The machine type is not P7 IH, so you had to create lpars by command line manually.';
    parentDiv.append(createInfoBar(showStr));
    return;
}
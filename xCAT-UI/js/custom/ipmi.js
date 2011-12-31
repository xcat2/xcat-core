/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
	// Load utility scripts (if any)
});

/**
 * Constructor
 * 
 * @return Nothing
 */
var ipmiPlugin = function() {

};

/**
 * Clone node (service page)
 * 
 * @param node
 * 			Node to clone
 * @return Nothing
 */
ipmiPlugin.prototype.serviceClone = function(node) {

};

/**
 * Load provision page (service page)
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
ipmiPlugin.prototype.loadServiceProvisionPage = function(tabId) {
	
};

/**
 * Show node inventory (service page)
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
ipmiPlugin.prototype.loadServiceInventory = function(data) {
	
};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
ipmiPlugin.prototype.loadInventory = function(data) {
	var args = data.msg.split(',');
	var tabId = args[0].replace('out=', '');
	var node = args[1].replace('node=', '');
	
	// Get node inventory
	var inv = data.rsp;

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div></div>');
	
	// Create a fieldset
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>Hardware</legend>');
	fieldSet.append(legend);
	
	var oList = $('<ol></ol>');
	fieldSet.append(oList);
	invDiv.append(fieldSet);

	// Loop through each line
	var item;
	for (var k = 0; k < inv.length; k++) {
		// Remove node name
		var attr = inv[k].replace(node + ': ', '');
		attr = jQuery.trim(attr);

		// Append attribute to list
		item = $('<li></li>');
		item.append(attr);
		oList.append(item);
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
ipmiPlugin.prototype.loadClonePage = function(node) {
	// Get nodes tab
	var tab = getNodesTab();
	var newTabId = node + 'CloneTab';

	// If there is no existing clone tab
	if (!$('#' + newTabId).length) {
		// Create info bar
		var infoBar = createInfoBar('Not supported');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
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
ipmiPlugin.prototype.loadProvisionPage = function(tabId) {
	// Get OS image names
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'tabdump',
			tgt : '',
			args : 'osimage',
			msg : ''
		},

		success : setOSImageCookies
	});

	// Get groups
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'extnoderange',
			tgt : '/.*',
			args : 'subgroups',
			msg : ''
		},

		success : setGroupsCookies
	});

	// Get provision tab instance
	var inst = tabId.replace('ipmiProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create info bar
	var infoBar = createInfoBar('Provision an iDataPlex. This will install an operating system onto the iDataPlex.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Create provision existing node division
	var provExisting = createIpmiProvisionExisting(inst);
	provForm.append(provExisting);
};

/**
 * Load resources
 * 
 * @return Nothing
 */
ipmiPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'ipmiResourceTab';
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
ipmiPlugin.prototype.addNode = function() {
    var diag = $('<div id="addIdplx" class="form"></div>');
    var info = createInfoBar('Add a node range');
    diag.append(info);
    
    // Create node inputs
    var nodeFieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>Node</legend>');
	nodeFieldSet.append(legend);
	diag.append(nodeFieldSet);
	
    var nodeInputs = '<div><label>Node: </label><input type="text"></div>' +
               '<div><label>MAC:</label><input type="text"></div>' + 
               '<div><label>IP: </label><input type="text"></div>' +
               '<div><label>Groups: </label><input type="text"></div>';    
    nodeFieldSet.append(nodeInputs);
    
    var bmcFieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>BMC</legend>');
	bmcFieldSet.append(legend);
	diag.append(bmcFieldSet);
	
	// Create BMC inputs
	var bmcInputs = '<div><label>BMC:</label><input type="text"></div>' +
     	'<div><label>IP:</label><input type="text"></div>' +
     	'<div><label>Groups:</label><input type="text"></div>';    
	 bmcFieldSet.append(bmcInputs);

    diag.dialog({
    	title: 'Add node',
        modal: true,
        width: 400,
        close: function(){$(this).remove();},
        buttons: {
            "OK" : function(){addIdataplex();},
            "Cancel": function(){$(this).dialog('close');}
        }
    });
};

/**
 * return steps name for hardware discovery wizard
 * 
 * @return Nothing
 */
ipmiPlugin.prototype.getStep = function(){
	return ['Basic Patterns', 'Swithes', 'Network', 'Services', 'Power on hardwares'];
};

/**
 * return steps's init function for hardware discovery wizard
 * 
 * @return Nothing
 */
ipmiPlugin.prototype.getInitFunction = function(){
	return [idataplexInitBasic, idataplexInitSwitch, idataplexInitNetwork, idataplexInitService, idataplexInitPowerOn];
};

ipmiPlugin.prototype.getNextFunction = function(){
	return [idataplexCheckBasic, undefined, idataplexCheckNetwork, undefined, undefined,];
};

/**
 * Add iDataPlex node range
 * 
 * @return Nothing
 */
function addIdataplex(){
    var tempArray = new Array();
    var errorMessage = '';
    var attr = '';
    var args = '';
    
    // Remove existing warnings
    $('#addIdplx .ui-state-error').remove();
    
    // Get input values
    $('#addIdplx input').each(function(){
        attr = $(this).val();
        if (attr) {
            tempArray.push($(this).val());
        } else {
            errorMessage = "Please provide a value for each missing field!";
            return false;
        }
    });
    
    if (errorMessage) {
        $('#addIdplx').prepend(createWarnBar(errorMessage));
        return;
    }
    
    // Create loader
    $('#addIdplx').append(createLoader());
    
    // Change dialog buttons
    $('#addIdplx').dialog('option', 'buttons', {
    	'Close':function(){
    		$('#addIdplx').dialog('close');
    	}
    });
    
    // Generate chdef arguments
    args = '-t;node;-o;' + tempArray[0] + ';mac=' + tempArray[1] + ';ip=' + tempArray[2] + ';groups=' + 
          tempArray[3] + ';mgt=ipmi;chain="runcmd=bmcsetup";netboot=xnba;nodetype=osi;profile=compute;' +
          'bmc=' + tempArray[4];
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        }
    });
     
    // Generate chdef arguments for BMC
    args = '-t;node;-o;' + tempArray[4] + ';ip=' + tempArray[5] + ';groups=' + tempArray[6];
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        },
        success: function(data) {
            $('#addIdplx img').remove();
            var message = '';
            for (var i in data.rsp) {
                message += data.rsp[i];
            }
            
            if (message) {
                $('#addIdplx').prepend(createInfoBar(message));
            }
        }
    });
}

/**
 * Create provision existing node division
 * 
 * @param inst
 *            Provision tab instance
 * @return Provision existing node division
 */
function createIpmiProvisionExisting(inst) {
	// Create provision existing division
	var provExisting = $('<div></div>');

	// Create VM fieldset
	var nodeFS = $('<fieldset></fieldset>');
	var nodeLegend = $('<legend>Node</legend>');
	nodeFS.append(nodeLegend);
	
	var nodeAttr = $('<div style="display: inline-table; vertical-align: middle; width: 85%; margin-left: 10px;"></div>');
	nodeFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
	nodeFS.append(nodeAttr);
	
	// Create image fieldset
	var imgFS = $('<fieldset></fieldset>');
	var imgLegend = $('<legend>Image</legend>');
	imgFS.append(imgLegend);
	
	var imgAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
	imgFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
	imgFS.append(imgAttr);
	
	provExisting.append(nodeFS, imgFS);
	
	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label for="provType">Group:</label>');
	group.append(groupLabel);

	// Turn on auto complete for group
	var dTableDivId = 'ipmiNodesDatatableDIV' + inst;	// Division ID where nodes datatable will be appended
	var groupNames = $.cookie('groups');
	if (groupNames) {
		// Split group names into an array
		var tmp = groupNames.split(',');

		// Create drop down for groups
		var groupSelect = $('<select></select>');
		groupSelect.append('<option></option>');
		for ( var i in tmp) {
			// Add group into drop down
			var opt = $('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
			groupSelect.append(opt);
		}
		group.append(groupSelect);

		// Create node datatable
		groupSelect.change(function() {
			// Get group selected
			var thisGroup = $(this).val();
			// If a valid group is selected
			if (thisGroup) {
				createNodesDatatable(thisGroup, dTableDivId);
			} // End of if (thisGroup)
		});
	} else {
		// If no groups are cookied
		var groupInput = $('<input type="text" name="group"/>');
		group.append(groupInput);
	}
	nodeAttr.append(group);

	// Create node input
	var node = $('<div></div>');
	var nodeLabel = $('<label for="nodeName">Nodes:</label>');
	var nodeDatatable = $('<div id="' + dTableDivId + '" style="display: inline-block; max-width: 800px;"><p>Select a group to view its nodes</p></div>');
	node.append(nodeLabel);
	node.append(nodeDatatable);
	nodeAttr.append(node);

	// Create boot method drop down
	var method = $('<div></div>');
	var methodLabel = $('<label for="method">Boot method:</label>');
	var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
	methodSelect.append('<option value=""></option>'
		+ '<option value="boot">boot</option>'
		+ '<option value="install">install</option>'
		+ '<option value="iscsiboot">iscsiboot</option>'
		+ '<option value="netboot">netboot</option>'
		+ '<option value="statelite">statelite</option>'
	);
	method.append(methodLabel);
	method.append(methodSelect);
	imgAttr.append(method);
	
	// Create operating system input
	var os = $('<div></div>');
	var osLabel = $('<label for="os">Operating system:</label>');
	var osInput = $('<input type="text" name="os"/>');
	osInput.one('focus', function() {
		var tmp = $.cookie('osvers');		
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete({
				source: tmp.split(',')
			});
		}
	});
	os.append(osLabel);
	os.append(osInput);
	imgAttr.append(os);

	// Create architecture input
	var arch = $('<div></div>');
	var archLabel = $('<label for="arch">Architecture:</label>');
	var archInput = $('<input type="text" name="arch"/>');
	archInput.one('focus', function() {
		var tmp = $.cookie('osarchs');
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete({
				source: tmp.split(',')
			});
		}
	});
	arch.append(archLabel);
	arch.append(archInput);
	imgAttr.append(arch);

	// Create profile input
	var profile = $('<div></div>');
	var profileLabel = $('<label for="profile">Profile:</label>');
	var profileInput = $('<input type="text" name="profile"/>');
	profileInput.one('focus', function() {
		var tmp = $.cookie('profiles');
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete({
				source: tmp.split(',')
			});
		}
	});
	profile.append(profileLabel);
	profile.append(profileInput);
	imgAttr.append(profile);

	/**
	 * Provision existing
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
		var ready = true;
		var errorMessage = '';

		// Get provision tab ID
		var thisTabId = 'ipmiProvisionTab' + inst;
		
		// Get nodes that were checked
		var dTableId = 'ipmiNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		if (!tgts) {
			errorMessage += 'You need to select a node. ';
			ready = false;
		}
		
		// Check booth method
		var boot = $('#' + thisTabId + ' select[name=bootMethod]');
		if (!boot.val()) {
			errorMessage += 'You need to select a boot method. ';
			boot.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			boot.css('border', 'solid #BDBDBD 1px');
		}
		
		// Check operating system image
		var os = $('#' + thisTabId + ' input[name=os]');
		if (!os.val()) {
			errorMessage += 'You need to select a operating system image. ';
			os.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			os.css('border', 'solid #BDBDBD 1px');
		}
		
		// Check architecture
		var arch = $('#' + thisTabId + ' input[name=arch]');
		if (!arch.val()) {
			errorMessage += 'You need to select an architecture. ';
			arch.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			arch.css('border', 'solid #BDBDBD 1px');
		}
		
		// Check profile
		var profile = $('#' + thisTabId + ' input[name=profile]');
		if (!profile.val()) {
			errorMessage += 'You need to select a profile. ';
			profile.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			profile.css('border', 'solid #BDBDBD 1px');
		}
		
		// If all inputs are valid, ready to provision
		if (ready) {			
			// Disable provision button
			$(this).attr('disabled', 'true');
			
			// Prepend status bar
			var statBar = createStatusBar('ipmiProvisionStatBar' + inst);
			statBar.append(createLoader(''));
			statBar.prependTo($('#' + thisTabId));

			// Disable all inputs
			var inputs = $('#' + thisTabId + ' input');
			inputs.attr('disabled', 'disabled');
						
			// Disable all selects
			var selects = $('#' + thisTabId + ' select');
			selects.attr('disabled', 'disabled');
															
			/**
			 * (1) Set operating system
			 */
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'nodeadd',
					tgt : '',
					args : tgts + ';noderes.netboot=xnba;nodetype.os=' + os.val() + ';nodetype.arch=' + arch.val() + ';nodetype.profile=' + profile.val() + ';nodetype.provmethod=' + boot.val(),
					msg : 'cmd=nodeadd;out=' + inst
				},

				success : updateIpmiProvisionExistingStatus
			});
		} else {
			// Show warning message
			var warn = createWarnBar(errorMessage);
			warn.prependTo($(this).parent().parent());
		}
	});
	provExisting.append(provisionBtn);

	return provExisting;
}

/**
 * Update the provision existing node status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateIpmiProvisionExistingStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get provision tab instance
	var inst = args[1].replace('out=', '');
	
	// Get provision tab and status bar ID
	var statBarId = 'ipmiProvisionStatBar' + inst;
	var tabId = 'ipmiProvisionTab' + inst;
	
	/**
	 * (2) Remote install
	 */
	if (cmd == 'nodeadd') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).find('div').append(prg);

		// Get parameters
		var os = $('#' + tabId + ' input[name="os"]').val();
		var profile = $('#' + tabId + ' input[name="profile"]').val();
		var arch = $('#' + tabId + ' input[name="arch"]').val();
		
		// Get nodes that were checked
		var dTableId = 'ipmiNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Begin installation
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'rinstall;' + os + ';' + profile + ';' + arch + ';' + tgts,
				msg : 'cmd=rinstall;out=' + inst
			},

			success : updateIpmiProvisionExistingStatus
		});
	} 
	
	/**
	 * (3) Done
	 */
	else if (cmd == 'rinstall') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).find('div').append(prg);
		$('#' + statBarId).find('img').remove();
		
		// If installation was successful
		if (prg.html().indexOf('Error') == -1) {
			$('#' + statBarId).find('div').append('<pre>It will take several minutes before the nodes are up and ready. Use nodestat to check the status of the install.</pre>');
		}
	}
}

/**
 * step 2: init the idataplex basic pattern
 * 
 * @param 
 * 
 * @return
 */
function idataplexInitBasic(){
    var tempip = '';
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showString = '<div style="min-height:360px" id="patternDiv"><h2>' + steps[currentStep] + '</h2>';
    showString += '<table><tbody>';
    //nodes title
    showString += '<tr><td><h3>Nodes:</h3></td></tr>';
    //nodes name range
    showString += '<tr><td>Name Range:</td><td><input type="text" title="node[1-167] or node1-node167" ' +
    'name="idataplexnodename" value="' + getDiscoverEnv('idataplexnodename') + '"></td>';
    //nodes start ip
    if (getDiscoverEnv('idataplexnodeip')){
        tempip = getDiscoverEnv('idataplexnodeip');
    }
    else{
        tempip = '172.30.20.1';
    }
    showString += '<td>Start IP:</td><td><input type="text" title="Format: XXX.XXX.XXX.1, last number must be 1.<br/> 172.30.20.1 is suggested." ' + 
          'name="idataplexnodeip" value="' + tempip + '"></td></tr>';
    //num-nodes-per-frame
    showString += '<tr><td>Nodes number <br/>per Frame:</td><td><input type="text" title="84: Each frame contains 84 nodes.<br/>Valide Number:20,21,40,41,42,84." '+
          'name="idataplexperframe" value="' + getDiscoverEnv('idataplexperframe') + '"></td><td></td><td></td></tr>';
    //bmc title
    showString += '<tr><td><h3>BMCs:</h3></td></tr>';
    //bmc name range
    showString += '<tr><td>Name Range:</td><td><input type="text" title="bmc[1-167] or bmc1-bmc167" ' +
    'name="idataplexbmcname" value="' + getDiscoverEnv('idataplexbmcname') + '"></td>';
    //bmc start ip
    if (getDiscoverEnv('idataplexbmcip')){
        tempip = getDiscoverEnv('idataplexbmcip');
    }
    else{
        tempip = '172.30.120.1';
    }
    showString += '<td>Start IP:</td><td><input type="text" title="Format: XXX.XXX.XXX.1, last number must be 1.<br/>172.30.120.1 is suggested." ' + 
          'name="idataplexbmcip" value="' + tempip + '"></td></tr>';
    //switches title
    showString += '<tr><td><h3>Switches:</h3></td></tr>';
    //switches name range
    showString += '<tr><td>Name Range:</td><td><input type="text" title="switch[1-4] or switch1-switch4" ' +
    'name="idataplexswitchname" value="' + getDiscoverEnv('idataplexswitchname') + '"></td>';
    //switches start ip
    if (getDiscoverEnv('idataplexswitchip')){
        tempip = getDiscoverEnv('idataplexswitchip');
    }
    else{
        tempip = '172.30.10.1';
    }
    showString += '<td>Start IP:</td><td><input type="text" title="Format: XXX.XXX.XXX.1, last number must be 1.<br/>172.30.10.1 is suggested." ' + 
          'name="idataplexswitchip" value="' + tempip + '"></td></tr>';
    //nodes per switch
    showString += '<tr><td>Nodes number <br/>per Switch:</td><td><input type="text" title="42: Each switch connect 42 nodes.<br/>Valide Number:20,21,40,41,42."' +
        'name="idataplexperswitch" value="' + getDiscoverEnv('idataplexperswitch') + '"></td><td></td><td></td></tr>';
    showString += '</tbody></table></div>';
    
    $('#discoverContentDiv').append(showString);
    
    $('#discoverContentDiv [title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 1
    });
    
    createDiscoverButtons();
}

/**
 * step 2: collect and check the basic pattern input on page.
 * 
 * @param 
 * 
 * @return   false: the input contains error, can not go to next step
 *           true : the input are correct, go to the next step
 */
function idataplexCheckBasic(operType){
    collectInputValue();

    //click back button, do not need check, only collect input value is ok.
    if ('back' == operType){
        return true;
    }
    
    $('#patternDiv .ui-state-error').remove();
    var errMessage = '';
    var nodename = getDiscoverEnv('idataplexnodename');
    var nodeip = getDiscoverEnv('idataplexnodeip');
    var bmcname = getDiscoverEnv('idataplexbmcname');
    var bmcip = getDiscoverEnv('idataplexbmcip');
    var switchname = getDiscoverEnv('idataplexswitchname');
    var switchip = getDiscoverEnv('idataplexswitchip');
    var nodesperswitch = getDiscoverEnv('idataplexperswitch');
    var nodesperframe = getDiscoverEnv('idataplexperframe');
    
    //all fields should input
    if (!nodename){
        errMessage += 'Input the Nodes name.<br/>';
    }
    
    if (!verifyIp(nodeip)){
        errMessage += 'Input valid Nodes start ip.<br/>';
    }
    
    if (!bmcname){
        errMessage += 'Input the BMC name.<br/>';
    }
    
    if (!verifyIp(bmcip)){
        errMessage += 'Input valid BMC start ip.<br/>';
    }
    
    if (!switchname){
        errMessage += 'Input the switch name.<br/>';
    }
    
    if (!verifyIp(switchip)){
        errMessage += 'Input valid switch start ip.<br/>';
    }
    
    if (!nodesperswitch){
        errMessage += 'Input the nodes number per switch.<br/>';
    }
    
    if (!nodesperframe){
        errMessage += 'Input the nodes number per frame.<br/>';
    }
    
    if ('' != errMessage){
        var warnBar = createWarnBar(errMessage);
        $('#patternDiv').prepend(warnBar);
        return false;
    }
    
    //check the relations among nodes, bmcs and switches
    var nodeNum = expandNR(nodename).length;
    var bmcNum = expandNR(bmcname).length;
    var switchNum = expandNR(switchname).length;
    var tempNumber = 0;
    
    //nodes number and bmc number
    if (nodeNum != bmcNum){
        errMessage += 'The number of Node must equal the number of BMC.<br/>';
    }
    
    //nodes' number calculate by switches
    tempNumber += Number(nodesperswitch) * switchNum;
    
    if (tempNumber < nodeNum){
        errMessage += 'Input the node number per switch correctly.<br/>';
    }
    
    if ('' != errMessage){
        var warnBar = createWarnBar(errMessage);
        $('#patternDiv').prepend(warnBar);
        return false;
    }

    return true;
}

/**
 * step 3: tell users to configure the switches.
 * 
 * @param 
 * 
 * @return
 */
function idataplexInitSwitch(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var switchArray = expandNR(getDiscoverEnv('idataplexswitchname'));
    var switchIp = getDiscoverEnv('idataplexswitchip');
    var showString = '<div style="min-height:360px" id="switchDiv"><h2>' + steps[currentStep] + '</h2>';
    showString += '<p>You defined ' + switchArray.length +' switches in last step. Configure them manually please:<br/>';
    showString += '<ul><li>1. Start IP address: ' + switchIp + ', and the IPs must be continuous.</li>';
    showString += '<li>2. Enable the SNMP agent on switches.</li>';
    showString += '<li>3. If you want to use the SNMP V3, the user/password and AuthProto (default is \'md5\') should be set in the switches table.</li>';
    showString += '<li>4. Click the next button.</li>';
    showString += '</p>';
    $('#discoverContentDiv').append(showString);
    
    createDiscoverButtons();
}

/**
 * step 4: init the interface and dhcp dynamic range for hardware discovery page.
 * 
 * @param 
 * 
 * @return
 */
function idataplexInitNetwork(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var startIp = '172.30.200.1';
    var endIp = '172.30.255.254';
    var showDiv = $('<div style="min-height:360px" id="networkDiv"><h2>' + steps[currentStep] + '</h2>');
    var infoBar = createInfoBar('Make sure the discovery NIC\'s IP, start IP addresses and DHCP dynamic IP range are in the same subnet.');
    showDiv.append(infoBar);
    //init the ip range by input
    if (getDiscoverEnv('idataplexIpStart')){
        startIp = getDiscoverEnv('idataplexIpStart');
    }
    
    if (getDiscoverEnv('idataplexIpEnd')){
        endIp = getDiscoverEnv('idataplexIpEnd');
    }
    var showString = '<table><tbody>';
    showString += '<tr><td>DHCP Dynamic Range:</td><td><input type="text" name="idataplexIpStart" value="' + startIp + 
        '" title="A start Ip address for DHCP dynamic range.<br/>172.30.200.1 is suggested.">-<input type="text" name="idataplexIpEnd" value="' + 
        endIp + '" title="This IP must larger than start IP, and the range must large than the number of nodes and bmcs.<br/>172.30.255.254 is suggested."></td></tr>';
    showString += '</tbody></table>';
    showDiv.append(showString);
    
    $('#discoverContentDiv').append(showDiv);
    
    $('#discoverContentDiv [title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 1
    });
    
    createDiscoverButtons();
}

/**
 * step 4: check the dynamic range for dhcp
 * 
 * @param 
 * 
 * @return
 */
function idataplexCheckNetwork(operType){
    collectInputValue();

    //click back button, do not need check, only collect input value is ok.
    if ('back' == operType){
        return true;
    }
    
    $('#networkDiv .ui-state-error').remove();
    var startIp = getDiscoverEnv('idataplexIpStart');
    var endIp = getDiscoverEnv('idataplexIpEnd');
    var errMessage = '';
    if(!verifyIp(startIp)){
        errMessage += 'Input the correct start IP address.<br/>';
    }
    
    if(!verifyIp(endIp)){
        errMessage += 'Input the correct end IP address.<br/>';
    }
    
    if ('' != errMessage){
        var warnBar = createWarnBar(errMessage);
        $('#networkDiv').prepend(warnBar);
        return false;
    }
    
    if (ip2Decimal(endIp) <= ip2Decimal(startIp)){
        var warnBar = createWarnBar('the end IP must larger than start IP.<br/>');
        $('#networkDiv').prepend(warnBar);
        return false;
    }
    
    return true;
}

/**
 * step 5: configure service by xcat command and restart 
 * 
 * @param 
 * 
 * @return
 */
function idataplexInitService(operType){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showStr = '<div style="min-height:360px" id="serviceDiv"><h2>' + steps[currentStep] + '</h2>';
    showStr += '<ul>';
    showStr += '<li id="fileLine"><span class="ui-icon ui-icon-wrench"></span>Create configure file for xcatsetup.</li>';
    showStr += '<li id="setupLine"><span class="ui-icon ui-icon-wrench"></span>Wrote Objects into xCAT database by xcatsetup.</li>';
    showStr += '<li id="hostsLine"><span class="ui-icon ui-icon-wrench"></span>Configure Hosts.</li>';
    showStr += '<li id="dnsLine"><span class="ui-icon ui-icon-wrench"></span>Configure DNS.</li>';
    showStr += '<li id="dhcpLine"><span class="ui-icon ui-icon-wrench"></span>Configure DHCP.</li>';
    showStr += '<li id="conserverLine"><span class="ui-icon ui-icon-wrench"></span>Configure Conserver.</li>';
    showStr += '</ul>';
    showStr += '</div>';
    $('#discoverContentDiv').append(showStr);
    
    if ('back' == operType){
        createDiscoverButtons();
        return;
    }
    
    idataplexCreateSetupFile();
}

/**
 * step 5: create the stanza file for xcatsetup
 * 
 * @param 
 * 
 * @return
 */
function idataplexCreateSetupFile(){
    var fileContent = '';
    
    //add the waiting loader on page
    $('#fileLine').append(createLoader());
    
    //site
    fileContent += "xcat-site:\n" + 
                   "  domain = cluster.com\n" +
                   "  cluster-type = idataplex\n";
    
    //xcat-service-lan
    fileContent += "xcat-service-lan:\n" +
                   "  dhcp-dynamic-range = " + getDiscoverEnv('idataplexIpStart') + "-" + getDiscoverEnv('idataplexIpEnd') + "\n";
    //xcat-switch
    fileContent += "xcat-switches:\n" +
                   "  hostname-range = " + getDiscoverEnv('idataplexswitchname') + "\n" +
                   "  starting-ip = " + getDiscoverEnv('idataplexswitchip') + "\n";
    
    //xcat-node
    fileContent += "xcat-nodes:\n" +
                   "  hostname-range = " + getDiscoverEnv('idataplexnodename') + "\n" +
                   "  starting-ip = " + getDiscoverEnv('idataplexnodeip') + "\n" +
                   "  num-nodes-per-switch = " + getDiscoverEnv('idataplexperswitch') + "\n" +
                   "  num-nodes-per-frame = " + getDiscoverEnv('idataplexperframe') + "\n";
    
    //xcat-bmc
    fileContent += "xcat-bmcs:\n" +
                   "  hostname-range = " + getDiscoverEnv('idataplexbmcname') + "\n" +
                   "  starting-ip = " + getDiscoverEnv('idataplexbmcip') + "\n";
    
    $.ajax({
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'echo -e "' + fileContent + '" > /tmp/webxcat.conf'
        },
        
        success : function(data){
            $('#fileLine img').remove();
            var tempSpan = $('#fileLine').find('span');
            tempSpan.removeClass('ui-icon-wrench');
            tempSpan.addClass('ui-icon-check');
            idataplexSetup();
        }
    });
}

/**
 * step 5: run xcatsetup to create the database for idataplex cluster
 * 
 * @param 
 * 
 * @return
 */
function idataplexSetup(){
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
        
        success : function(data){
            $('#setupLine img').remove();
            var tempSpan = $('#setupLine').find('span');
            tempSpan.removeClass('ui-icon-wrench');
            tempSpan.addClass('ui-icon-check');
            idataplexMakehosts();
        }
    });
}
/**
 * step 5: run makehosts for idataplex
 * 
 * @param 
 * 
 * @return
 */
function idataplexMakehosts(){
    createDiscoverButtons();
}
/**
 * step 5: run makedns for idataplex
 * 
 * @param 
 * 
 * @return
 */
function idataplexMakedns(){
    
}
/**
 * step 5: run make dhcp for idataplex
 * 
 * @param 
 * 
 * @return
 */
function idataplexMakedhcp(){
    
}
/**
 * step 5: run make conserver for idataplex
 * 
 * @param 
 * 
 * @return
 */
function idataplexMakeconserver(){
    
}
/**
 * step 6: tell users to power on all hardware for discovery
 * 
 * @param 
 * 
 * @return
 */
function idataplexInitPowerOn(){
    $('#discoverContentDiv').empty();
    $('.tooltip').remove();
    var showString = '<div style="min-height:360px" id="poweronDiv"><h2>' + steps[currentStep] + '</h2>';
    showString += 'Walk over to each idataplex server and push the power button to power on. <br/>' +
                  'After about 5-10 minutes, nodes should be configured and ready for hardware management.<br/>';
    $('#discoverContentDiv').append(showString);
    
    //add the refresh button
    var refreshButton = createButton("Refresh");
    $('#poweronDiv').append(refreshButton);
    refreshButton.bind('click', function(){
        var tempObj = $('#poweronDiv div p');
        tempObj.empty().append(createLoader());
        
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'rpower',
                tgt : 'all',
                args : 'stat',
                msg : ''
            },
            
            success : function(data){
                var tempObj = $('#poweronDiv div p');
                tempObj.empty();
                for(var i in data.rsp){
                    tempObj.append(data.rsp[i] + '<br/>');
                }
            }
        });
    });
    
    //add the info area
    var infoBar = createInfoBar('Click the refresh button to check all nodes\' status.');
    $('#poweronDiv').append(infoBar);
    createDiscoverButtons();
}
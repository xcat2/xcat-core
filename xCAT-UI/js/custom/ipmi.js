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
	var provExisting = createIpmpProvisionExisting(inst);
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
    var diag = $('<div id="addIdplx" class="form" title="Add iDataPlex"></div>');
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
            errorMessage = "You are missing some inputs!";
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
function createIpmpProvisionExisting(inst) {
	// Create provision existing division
	var provExisting = $('<div></div>');

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
	provExisting.append(group);

	// Create node input
	var node = $('<div></div>');
	var nodeLabel = $('<label for="nodeName">Nodes:</label>');
	var nodeDatatable = $('<div id="' + dTableDivId + '" style="display: inline-block; max-width: 800px;"><p>Select a group to view its nodes</p></div>');
	node.append(nodeLabel);
	node.append(nodeDatatable);
	provExisting.append(node);

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
	provExisting.append(method);
	
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
	provExisting.append(os);

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
	provExisting.append(arch);

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
	provExisting.append(profile);

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
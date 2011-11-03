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
var esxPlugin = function() {

};

/**
 * Clone node (service page)
 * 
 * @param node
 * 			Node to clone
 * @return Nothing
 */
esxPlugin.prototype.serviceClone = function(node) {

};

/**
 * Load provision page (service page)
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
esxPlugin.prototype.loadServiceProvisionPage = function(tabId) {
	
};

/**
 * Show node inventory (service page)
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
esxPlugin.prototype.loadServiceInventory = function(data) {
	
};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
esxPlugin.prototype.loadInventory = function(data) {
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
esxPlugin.prototype.loadClonePage = function(node) {
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
esxPlugin.prototype.loadProvisionPage = function(tabId) {
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
	var inst = tabId.replace('esxProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create info bar
	var infoBar = createInfoBar('Provision an ESX virtual machine.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);
	
	var vmFS = $('<fieldset></fieldset>');
	var vmLegend = $('<legend>Virtual Machine</legend>');
	vmFS.append(vmLegend);
	
	var hwFS = $('<fieldset></fieldset>');
	var hwLegend = $('<legend>Hardware</legend>');
	hwFS.append(hwLegend);
	
	var imgFS = $('<fieldset></fieldset>');
	var imgLegend = $('<legend>Image</legend>');
	imgFS.append(imgLegend);
	
	provForm.append(vmFS, hwFS, imgFS);
	
	// Create hypervisor input
	var hypervisor = $('<div></div>');
	var hypervisorLabel = $('<label>Hypervisor:</label>');
	hypervisor.append(hypervisorLabel);

	// Turn on auto complete for group
	var hypervisorNames = $.cookie('');
	if (hypervisorNames) {
		// Split group names into an array
		var tmp = groupNames.split(',');

		// Create drop down for groups
		var hypervisorSelect = $('<select></select>');
		hypervisorSelect.append('<option></option>');
		for ( var i in tmp) {
			// Add group into drop down
			var opt = $('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
			hypervisorSelect.append(opt);
		}
		hypervisor.append(groupSelect);
	} else {
		// If no groups are cookied
		var hypervisorInput = $('<input type="text" name="group"/>');
		hypervisor.append(hypervisorInput);
	}
	vmFS.append(hypervisor);
	
	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label>Group:</label>');
	group.append(groupLabel);

	// Turn on auto complete for group
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
	} else {
		// If no groups are cookied
		var groupInput = $('<input type="text" name="group"/>');
		group.append(groupInput);
	}
	vmFS.append(group);

	// Create node input
	var node = $('<div></div>');
	var nodeLabel = $('<label>VM name:</label>');
	var nodeInput = $('<input type="text" name="node"/>');
	node.append(nodeLabel);
	node.append(nodeInput);
	vmFS.append(node);

	// Create memory input
	var memory = $('<div></div>');
	var memoryLabel = $('<label>Memory:</label>');
	var memoryInput = $('<input type="text" name="memory"/>');
	memory.append(memoryLabel);
	memory.append(memoryInput);
	hwFS.append(memory);
	
	// Create processor dropdown
	var cpu = $('<div></div>');
	var cpuLabel = $('<label>Processor:</label>');
	var cpuSelect = $('<select name="cpu"></select>');
	cpuSelect.append('<option value="1">1</option>'
		+ '<option value="2">2</option>'
		+ '<option value="3">3</option>'
		+ '<option value="4">4</option>'
		+ '<option value="5">5</option>'
		+ '<option value="6">6</option>'
		+ '<option value="7">7</option>'
		+ '<option value="8">8</option>'
	);
	cpu.append(cpuLabel);
	cpu.append(cpuSelect);
	hwFS.append(cpu);
	
	// Create NIC dropdown
	var nic = $('<div></div>');
	var nicLabel = $('<label>NIC:</label>');
	var nicSelect = $('<select name="nic"></select>');
	nicSelect.append('<option value="1">1</option>'
		+ '<option value="2">2</option>'
		+ '<option value="3">3</option>'
		+ '<option value="4">4</option>'
		+ '<option value="5">5</option>'
		+ '<option value="6">6</option>'
		+ '<option value="7">7</option>'
		+ '<option value="8">8</option>'
	);
	nic.append(nicLabel);
	nic.append(nicSelect);
	hwFS.append(nic);
	
	// Create disk input
	var disk = $('<div></div>');
	var diskLabel = $('<label>Disk size:</label>');
	var diskInput = $('<input type="text" name="disk"/>');
	var diskSizeSelect = $('<select name="nic"></select>');
	diskSizeSelect.append('<option value="MB">MB</option>'
		+ '<option value="GB">GB</option>'
	);
	disk.append(diskLabel, diskInput, diskSizeSelect);
	hwFS.append(disk);
	
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
	imgFS.append(os);
	
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
	imgFS.append(arch);
	
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
	imgFS.append(profile);
	
	// Create boot method dropdown
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
	imgFS.append(method);

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
		var thisTabId = 'esxProvisionTab' + inst;
	});
	provForm.append(provisionBtn);
};

/**
 * Load resources
 * 
 * @return Nothing
 */
esxPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'esxResourceTab';
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
esxPlugin.prototype.addNode = function() {
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
          tempArray[3] + ';mgt=esx;chain="runcmd=bmcsetup";netboot=xnba;nodetype=osi;profile=compute;' +
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
 * Update the provision node status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateESXProvisionStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get provision tab instance
	var inst = args[1].replace('out=', '');
	
	// Get provision tab and status bar ID
	var statBarId = 'esxProvisionStatBar' + inst;
	var tabId = 'esxProvisionTab' + inst;
	
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
		var dTableId = 'esxNodesDatatable' + inst;
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

			success : updateESXProvisionStatus
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
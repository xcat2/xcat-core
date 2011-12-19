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
var bladePlugin = function() {

};

/**
 * Clone node (service page)
 * 
 * @param node
 * 			Node to clone
 * @return Nothing
 */
bladePlugin.prototype.serviceClone = function(node) {

};

/**
 * Load provision page (service page)
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
bladePlugin.prototype.loadServiceProvisionPage = function(tabId) {
	
};

/**
 * Show node inventory (service page)
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
bladePlugin.prototype.loadServiceInventory = function(data) {
	
};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
bladePlugin.prototype.loadInventory = function(data) {
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
		// Remove node name in front
		var str = inv[k].replace(node + ': ', '');
		str = jQuery.trim(str);

		// Append the string to a list
		item = $('<li></li>');
		item.append(str);
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
bladePlugin.prototype.loadClonePage = function(node) {
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
bladePlugin.prototype.loadProvisionPage = function(tabId) {
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
	var inst = tabId.replace('bladeProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create info bar
	var infoBar = createInfoBar('Provision a blade. This will install an operating system onto the blade.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Create provision existing node division
	var provExisting = createBladeProvisionExisting(inst);
	provForm.append(provExisting);
};

/**
 * Load resources
 * 
 * @return Nothing
 */
bladePlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'bladeResourceTab';
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
bladePlugin.prototype.addNode = function() {
    var addNodeForm = $('<div id="addBladeCenter" class="form"></div>');
    var info = createInfoBar('Add a BladeCenter node');
	addNodeForm.append(info);
    
    var typeFS = $('<fieldset></fieldset>');
	var typeLegend = $('<legend>Type</legend>');
	typeFS.append(typeLegend);
	addNodeForm.append(typeFS);
	
	var nodeFS = $('<fieldset id="nodeAttrs"></fieldset>');
	var nodeLegend = $('<legend>Node</legend>');
	nodeFS.append(nodeLegend);
	addNodeForm.append(nodeFS);
	
	typeFS.append('<div>' + 
			'<label>Node type:</label>' +
    		'<select id="typeSelect">' +
            	'<option value="mm">AMM</option>' +
            	'<option value="blade">Blade</option>' +
            	'<option value="scanmm">Blade by scan</option>' +
            '</select>' +
	'</div>');
    
	typeFS.find('#typeSelect').bind('change', function(){
		// Remove any existing warnings
    	$('#addBladeCenter .ui-state-error').remove();
    	nodeFS.find('div').remove();
    	
        var addMethod = $(this).val();
        switch(addMethod){
        	case 'mm':
        		nodeFS.append('<div><label>AMM name: </label><input id="ammName" type="text"/></div>');
        		nodeFS.append('<div><label>Username: </label><input type="text"></div>');
        		nodeFS.append('<div><label>Password: </label><input type="text"></div>');
        		nodeFS.append('<div><label>AMM IP: </label><input id="ammIp" type="text"/></div>');
        		break;
        	case 'blade':
        		nodeFS.append('<div><label>Blade name: </label><input id="bladeName" type="text"/></input></div>');
        		nodeFS.append('<div><label>Blade group: </label><input id="bladeGroup" type="text"/></input></div>');
        		nodeFS.append('<div><label>Blade ID: </label><input id="bladeId" type="text"/t></div>');
        		nodeFS.append('<div><label>Blade series: </label>JS <input type="radio" name="series" value="js"/> LS<input type="radio" name="series" value="ls"/></div>');
        		nodeFS.append('<div><label style="vertical-align: middle;">Blade MPA: </label><select id="mpaSelect"></select><div>');
        		break;
        	case 'scanmm':
        		nodeFS.append('<div><label style="vertical-align: middle;">Blade MPA: </label><select id="mpaSelect"></select></div>');
        		break;
        }
        
        // Change dialog width
		if ($(this).val() == 'scanmm'){
			$('#addBladeCenter').dialog('option', 'width', '650');
		}else{
			$('#addBladeCenter').dialog('option', 'width', '400');
		}
		
		// If MM node, return directly
		if ($(this).val() == 'mm'){
			return;
		}
		
		// Get all MM nodes from server side
		nodeFS.find('select:eq(0)').after(createLoader());
       
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
               	cmd : 'lsdef',
               	tgt : '',
               	args : '-t;node;-w;mgt==blade;-w;id==0',
               	msg : addMethod
           	},
           	success : function(data){
           		var position = 0;
           		var tempStr = '';
           		var options = '';
           		
           		// Remove the loading image
           		nodeFS.find('img').remove();
               
           		// Check return result
           		if (data.rsp.length < 1) {
           			$('#addBladeCenter').prepend(createWarnBar('Please define MM node first!'));
           			return;
           		}
               
           		// Add all MM nodes to select
           		for (var i in data.rsp){
           			tempStr = data.rsp[i];
           			position = tempStr.indexOf(' ');
           			tempStr = tempStr.substring(0, position);
           			options += '<option value="' + tempStr + '">' + tempStr + '</option>';
           		}
               
           		nodeFS.find('select:eq(0)').append(options);
           		
           		// If adding node by rscan, we should add the scan button
           		if (data.msg != 'scanmm') {
           			return;
           		}
           		
           		var scan = createButton('Scan');
       			scan.bind('click', function(){
       				var mmName = nodeFS.find('select:eq(0)').val();
       				nodeFS.prepend(createLoader());
       				$('#nodeAttrs button').attr('disabled', 'disabled');
       				$.ajax({
       					url : 'lib/cmd.php',
       			        dataType : 'json',
       			        data : {
       			            cmd : 'rscan',
       			            tgt : mmName,
       			            args : '',
       			            msg : ''
       			        },
       			        
       			        success: function(data){
       			        	showScanMmResult(data.rsp[0]);
       			        }
       				});
       			});
       			
       			nodeFS.find('select:eq(0)').after(scan);
           	}
		});
    });
    
    addNodeForm.dialog( {
        modal : true,
        width : 400,
        title : 'Add node',
        open : function(event, ui) {
            $(".ui-dialog-titlebar-close").hide();
        },
        close : function(){
        	$(this).remove();
        },
        buttons : {
            'Ok' : function() {
                // Remove any existing warnings
                $('#addBladeCenter .ui-state-error').remove();
                var addMethod = $('#typeSelect').val();
                
                if (addMethod == "mm") {
                    addMmNode();
                } else if(addMethod == "blade") {
                    addBladeNode();
                } else{
                	addMmScanNode();
                }
            },
            'Cancel' : function() {
                $(this).remove();
            }
        }
    });
    
    addNodeForm.find('#typeSelect').trigger('change');
};


/**
 * Add AMM node
 * 
 * @return Nothing
 */
function addMmNode(){
	var argsTmp = '';
	var errorMsg = '';
    
	$('#addBladeCenter input').each(function(){
		if (!$(this).val()) {
			errorMsg = 'Please provide a value for each missing field.';
		}
		
		argsTmp += $(this).val() + ',';
	});
	
	if (errorMsg) {
		// Add warning message
		$('#addBladeCenter').prepend(createWarnBar(errorMsg));
		return;
	}

	argsTmp = argsTmp.substring(0, argsTmp.length - 1);
    
	// Add the loader
    $('#addBladeCenter').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;mm;' + argsTmp,
            msg : ''
        },
        success : function(data) {
            $('#addBladeCenter').find('img').remove();
            var info = createInfoBar('Successfully added MM node.');
            $('#addBladeCenter').prepend(info);
            $('#addBladeCenter').dialog("option", "buttons", {
                "Close" : function() {
                    $('#addBladeCenter').dialog('close');
                    $('.selectgroup').trigger('click');
                }
            });
        }
    });
}

/**
 * Add blade node
 * 
 * @return Nothing
 */
function addBladeNode(){
    var name = $('#addBladeCenter #bladeName').val();
    var group = $('#addBladeCenter #bladeGroup').val();
    var id = $('#addBladeCenter #bladeId').val();
    var series = $("#addBladeCenter #bladeNode :checked").val();
    var mpa = $('#addBladeCenter #mpaSelect').val();

    var argsTmp = '-t;node;-o;' + name + ';id=' + id + 
            ';nodetype=osi;groups=' + group + ';mgt=blade;mpa=' + mpa + ';serialflow=hard';
    if (series != 'js') {
        argsTmp += ';serialspeed=19200;serialport=1';
    }
    
    if ((!name) || (!group) || (!id) || (!mpa)){
        $('#addBladeCenter').prepend(createWarnBar("Please provide a value for each missing field."));
        return;
    }

    // Add loader and disable buttons
    $('#addBladeCenter').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : argsTmp,
            msg : ''
        },
        success : function(data) {
            $('#addBladeCenter').find('img').remove();
            var messages = data.rsp;
            var notes = "";
            for (var i = 0; i < messages.length; i++) {
                notes += messages[i] + " ";
            }

            $('#addBladeCenter').prepend(createInfoBar(notes));
            $('#addBladeCenter').dialog("option", "buttons", {
                "Close" : function() {
                    $('#addBladeCenter').remove();
                }
            });
        }
    });
}

/**
 * Show rscan results
 * 
 * @param rscanResults
 *            Results from rscan of blade MPA
 * @return Nothing
 */
function showScanMmResult(rscanResults){
	var results = $('<div style="height: 300px; overflow: auto;" id="scan_results"></div>');
	var rscanTable = $('<table></table>');
	var regex = /\S+/g;
	var line = '';
	var column = 0;
	
	$('#nodeAttrs #scan_results').remove();
	$('#nodeAttrs img').remove();
	$('#nodeAttrs button').attr('disabled', '');
	if (!rscanResults){
		return;
	}
	
	var rows = rscanResults.split("\n");
	if (rows.length < 2){
		results.append(createWarnBar(rows[0]));
		$('#nodeAttrs').append(results);
		return;
	}
	
	// Add the table header
	var fields = rows[0].match(regex);
	column = fields.length;
	row = '<tr><td><input type="checkbox" onclick="selectAllRscanNode(this)"></td>';
	for(var i in fields){
		row += '<td>' + fields[i] + '</td>';
	}
	rscanTable.append(row);
	
	// Add the tbody
	for (var i=1; i<rows.length; i++) {
		line = rows[i];
		
		if (!line) {
			continue;
		}
		
		var fields = line.match(regex);
		if ('mm' == fields[0]){
			continue;
		}
		
		row = '<tr><td><input type="checkbox" name="' + fields[1] + '"></td>';
		
		for (var j=0; j<column; j++){
			row += '<td>';
			if (fields[j]) {
				if (j == 1) {
					row += '<input value="' + fields[j] + '">';
				} else {
					row += fields[j];
				}
			}
			
			row += '</td>';
		}
		row += '</tr>';
		rscanTable.append(row);
	}
	
	results.append(rscanTable);
	$('#nodeAttrs').prepend(results);
}

function addMmScanNode(){
	// Get the MM name
	var mmName = $('#nodeAttrs select').val();
	var nodeName = '';
	
	$('#nodeAttrs :checked').each(function() {
		if ($(this).attr('name')) {
			nodeName += $(this).attr('name') + ',';
			nodeName += $(this).parents('tr').find('input').eq(1).val() + ',';
		}
	});
	
	if (!nodeName) {
		alert('You should select nodes first!');
		return;
	}
	
	// Disabled the button
	$('.ui-dialog-buttonpane button').attr('disabled', 'disabled');
	
	nodeName = nodeName.substr(0, nodeName.length - 1);
	$('#nodeAttrs').append(createLoader());
	
	// Send the add request
	$.ajax({
		url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;node;' + mmName + ',' + nodeName,
            msg : ''
        },
        success : function(data){
        	// Refresh the area on the right side
        	$('#addBladeCenter').dialog('close');
        	$('.selectgroup').trigger('click');
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
function createBladeProvisionExisting(inst) {
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
	var dTableDivId = 'bladeNodesDatatableDIV' + inst;	// Division ID where nodes datatable will be appended
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
		var thisTabId = 'bladeProvisionTab' + inst;
		
		// Get nodes that were checked
		var dTableId = 'bladeNodesDatatable' + inst;
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
			var statBar = createStatusBar('bladeProvisionStatBar' + inst);
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

				success : updateBladeProvisionExistingStatus
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
function updateBladeProvisionExistingStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get provision tab instance
	var inst = args[1].replace('out=', '');
	
	// Get provision tab and status bar ID
	var statBarId = 'bladeProvisionStatBar' + inst;
	var tabId = 'bladeProvisionTab' + inst;
	
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
		var dTableId = 'bladeNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Begin installation
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rbootseq',
				tgt : tgts,
				args : 'net,hd',
				msg : 'cmd=rbootseq;out=' + inst
			},

			success : updateBladeProvisionExistingStatus
		});
	} 
	
	/**
	 * (3) Prepare node for boot
	 */
	if (cmd == 'nodeadd') {
		// Get provision method
		var bootMethod = $('#' + tabId + ' select[name=bootMethod]').val();
		
		// Get nodes that were checked
		var dTableId = 'bladeNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Prepare node for boot
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'nodeset',
				tgt : tgts,
				args : bootMethod,
				msg : 'cmd=nodeset;out=' + inst
			},

			success : updateBladeProvisionExistingStatus
		});
	}
	
	/**
	 * (4) Power on node
	 */
	if (cmd == 'nodeset') {
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).find('div').append(prg);
		
		// Get nodes that were checked
		var dTableId = 'bladeNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Prepare node for boot
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rpower',
				tgt : tgts,
				args : 'boot',
				msg : 'cmd=rpower;out=' + inst
			},

			success : updateBladeProvisionExistingStatus
		});
	}
	
	/**
	 * (5) Done
	 */
	else if (cmd == 'rpower') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).find('div').append(prg);
		$('#' + statBarId).find('img').remove();
		
		// If installation was successful
		if (prg.html().indexOf('Error') == -1) {
			$('#' + statBarId).find('div').append('<pre>It will take several minutes before the nodes are up and ready. Use rcons to monitor the status of the install.</pre>');
		}
	}
}
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
    var nodeTypeSelectDia = $('<div id="nodeTypeSelectDia" class="form"></div>');
    nodeTypeSelectDia.append('<div><label for="mgt">Node Type :</label><select id="nodeTypeSelect">' +
            '<option value="mm">AMM Node</option><option value="blade">Blade Node</option></select></div>');
    //append the mm div
    var mmStr = '<div id="mmNode">' +
                   '<label>AMM Name: </label><input id="ammName" type="text"></input><br/><br/>' +
                   '<label>AMM IP: </label><input id="ammIp" type="text"></input>' +
                   '</div>';
    
    //append the blade div
    var bladeStr = '<div id="bladeNode" style="display:none;">' +
                   '<label>Blade Name: </label><input id="bladeName" type="text"></input><br/><br/>' +
                   '<label>Blade Group: </label><input id="bladeGroup" type="text"></input><br/><br/>' +
                   '<label>Blade ID: </label><input id="bladeId" type="text"></input><br/><br/>' +
                   '<label>Blade Series: </label><input type="radio" name="series" value="js"/>JS<input type="radio" name="series" value="ls"/>LS<br/><br/>' +
                   '<label>Blade MPA: </label><select id="mpaSelect"></select>';
    nodeTypeSelectDia.append(mmStr);
    nodeTypeSelectDia.append(bladeStr);
    
    nodeTypeSelectDia.find('#nodeTypeSelect').bind('change', function(){
       $('#nodeTypeSelectDia .ui-state-error').remove();
       $('#mmNode').toggle();
       $('#bladeNode').toggle();
       if ('mm' == $(this).val()){
           return;
       }
       
       //get all mm nodes from the server side
       $('#bladeNode select').empty();
       $('#bladeNode').append(createLoader());
       
       $.ajax({
           url : 'lib/cmd.php',
           dataType : 'json',
           data : {
               cmd : 'lsdef',
               tgt : '',
               args : '-t;node;-w;mgt==blade;-w;id==0',
               msg : ''
           },
           success : function(data){
               var position = 0;
               var tempStr = '';
               var options = '';
               //remove the loading image
               $('#bladeNode img').remove();
               
               //check return result
               if (1 > data.rsp.length){
                   $('#nodeTypeSelectDia').prepend(createWarnBar('Please define MM node first!'));
                   return;
               }
               
               //add all mm nodes to select
               for (var i in data.rsp){
                   tempStr = data.rsp[i];
                   position = tempStr.indexOf(' ');
                   tempStr = tempStr.substring(0, position);
                   options += '<option value="' + tempStr + '">' + tempStr + '</option>';
               }
               
               $('#bladeNode select').append(options);
           }
       });
    });
    
    nodeTypeSelectDia.dialog( {
        modal : true,
        width : 400,
        title : 'Select Node Type',
        open : function(event, ui) {
            $(".ui-dialog-titlebar-close").hide();
        },
        buttons : {
            'Ok' : function() {
                //remove all error bar
                $('#nodeTypeSelectDia .ui-state-error').remove();
                
                if ($('#nodeTypeSelect').attr('value') == "mm") {
                    addMmNode();
                }
                else {
                    addBladeNode();
                }
            },
            'Cancel' : function() {
                $(this).remove();
            }
        }
    });
};

function addMmNode(){
    var name = $('#ammName').val();
    var ip = $('#ammIp').val();
    
    if ((!name) || (!ip)){
        $('#nodeTypeSelectDia').prepend(createWarnBar("You are missing some inputs!"));
        return;
    }
    
    //add the loader
    $('#nodeTypeSelectDia').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    var argsTmp = '-t;node;-o;' + name + 
            ';id=0;nodetype=mm;groups=mm;mgt=blade;mpa=' + name + ';ip=' + ip;
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
            $('#nodeTypeSelectDia').find('img').remove();
            var messages = data.rsp;
            var notes = "";
            for ( var i = 0; i < messages.length; i++) {
                notes += messages[i];
            }
            var info = createInfoBar(notes);
            $('#nodeTypeSelectDia').prepend(info);
            $('#nodeTypeSelectDia').dialog("option", "buttons", {
                "close" : function() {
                    $('#nodeTypeSelectDia').remove();
                }
            });
        }
    });
}

function addBladeNode(){
    var name = $('#bladeName').val();
    var group = $('#bladeGroup').val();
    var id = $('#bladeId').val();
    var series = $("#bladeNode :checked").val();
    var mpa = $('#mpaSelect').val();

    var argsTmp = '-t;node;-o;' + name + ';id=' + id + 
            ';nodetype=osi;groups=' + group + ';mgt=blade;mpa=' + mpa + ';serialflow=hard';
    if (series != 'js') {
        argsTmp += ';serialspeed=19200;serialport=1';
    }
    
    if ((!name) || (!group) || (!id) || (!mpa)){
        $('#nodeTypeSelectDia').prepend(createWarnBar("You miss some inputs."));
        return;
    }

    //add loader and disable buttons
    $('#nodeTypeSelectDia').prepend(createLoader());
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
            $('#nodeTypeSelectDia').find('img').remove();
            var messages = data.rsp;
            var notes = "";
            for ( var i = 0; i < messages.length; i++) {
                notes += messages[i];
            }

            $('#nodeTypeSelectDia').prepend(createInfoBar(notes));
            $('#nodeTypeSelectDia').dialog("option", "buttons", {
                "close" : function() {
                    $('#nodeTypeSelectDia').remove();
                }
            });
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
					args : tgts + ';noderes.netboot=xnba;nodetype.os=' + os.val() + ';nodetype.arch=' + arch.val() + ';nodetype.profile=' + profile.val(),
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
 * Create nodes datatable for a given group
 * 
 * @param group
 *            Group name
 * @param outId
 *            Division ID to append datatable
 * @return Nodes datatable
 */
function createNodesDatatable(group, outId) {
	// Get group nodes
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'lsdef',
			tgt : '',
			args : group,
			msg : outId
		},

		/**
		 * Create nodes datatable
		 * 
		 * @param data
		 *            Data returned from HTTP request
		 * @return Nothing
		 */
		success : function(data) {
			// Data returned
    		var rsp = data.rsp;
    
    		// Get output ID
    		var outId = data.msg;
    		// Get datatable ID
    		var dTableId = outId.replace('DIV', '');
    
    		// Node attributes hash
    		var attrs = new Object();
    		// Node attributes
    		var headers = new Object();
    
    		// Clear nodes datatable division
    		$('#' + outId).empty();
    
    		// Create nodes datatable
    		var node, args;
    		for ( var i in rsp) {
    			// Get node
    			var pos = rsp[i].indexOf('Object name:');
    			if (pos > -1) {
    				var temp = rsp[i].split(': ');
    				node = jQuery.trim(temp[1]);
    
    				// Create a hash for the node attributes
    				attrs[node] = new Object();
    				i++;
    			}
    
    			// Get key and value
    			args = rsp[i].split('=');
    			var key = jQuery.trim(args[0]);
    			var val = jQuery.trim(args[1]);
    
    			// Create hash table
    			attrs[node][key] = val;
    			headers[key] = 1;
    		}
    
    		// Sort headers
    		var sorted = new Array();
    		for ( var key in headers) {
    			sorted.push(key);
    		}
    		sorted.sort();
    
    		// Add column for check box and node
    		sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'node');
    
    		// Create nodes datatable
    		var dTable = new DataTable(dTableId);
    		dTable.init(sorted);
    
    		// Go through each node
    		for ( var node in attrs) {
    			// Create a row
    			var row = new Array();
    			// Create a check box
    			var checkBx = '<input type="checkbox" name="' + node + '"/>';
    			row.push(checkBx, node);
    
    			// Go through each header
    			for ( var i = 2; i < sorted.length; i++) {
    				// Add node attributes to the row
    				var key = sorted[i];
    				var val = attrs[node][key];
    				if (val) {
    					row.push(val);
    				} else {
    					row.push('');
    				}
    			}
    
    			// Add row to table
    			dTable.add(row);
    		}

    		$('#' + outId).append(dTable.object());
    		$('#' + dTableId).dataTable();
    	} // End of function(data)
	});
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
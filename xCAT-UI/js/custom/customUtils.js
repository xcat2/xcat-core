var provisionClock;

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
 * Create provision existing node division
 * 
 * @param plugin
 * 			  Plugin name to create division for
 * @param inst
 *            Provision tab instance
 * @return Provision existing node division
 */
function createProvisionExisting(plugin, inst) {
	// Create provision existing division and hide it
	var provExisting = $('<div></div>').hide();

	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label for="provType">Group:</label>');
	group.append(groupLabel);

	// Turn on auto complete for group
	var dTableDivId = plugin + 'NodesDatatableDIV' + inst;	// Division ID where nodes datatable will be appended
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
	var nodeDatatable = $('<div class="indent" id="' + dTableDivId + '"><p>Select a group to view its nodes</p></div>');
	node.append(nodeLabel);
	node.append(nodeDatatable);
	provExisting.append(node);

	// Create boot method drop down
	var method = $('<div></div>');
	var methodLabel = $('<label for="method">Boot method:</label>');
	var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
	methodSelect.append('<option value="boot">boot</option>'
		+ '<option value="install">install</option>'
		+ '<option value="iscsiboot">iscsiboot</option>'
		+ '<option value="netboot">netboot</option>'
		+ '<option value="statelite">statelite</option>'
	);
	method.append(methodLabel);
	method.append(methodSelect);
	provExisting.append(method);

	// Create boot type drop down
	var type = $('<div></div>');
	var typeLabel = $('<label for="type">Boot type:</label>');
	var typeSelect = $('<select id="bootType" name="bootType"></select>');
	typeSelect.append('<option value="pxe">pxe</option>'
		+ '<option value="iscsiboot">yaboot</option>'
		+ '<option value="zvm">zvm</option>'
	);
	type.append(typeLabel);
	type.append(typeSelect);
	provExisting.append(type);

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
		// TODO Insert provision code here
		openDialog('info', 'Under construction');
	});
	provExisting.append(provisionBtn);

	return provExisting;
}

/**
 * Create provision new node division
 * 
 * @param inst
 *            Provision tab instance
 * @return Provision new node division
 */
function createProvisionNew(plugin, inst) {
	// Create provision new node division
	var provNew = $('<div></div>');

	// Create node input
	var nodeName = $('<div><label for="nodeName">Node:</label><input type="text" name="nodeName"/></div>');
	provNew.append(nodeName);

	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label for="group">Group:</label>');
	var groupInput = $('<input type="text" name="group"/>');
	groupInput.one('focus', function() {
		var groupNames = $.cookie('groups');
		if (groupNames) {
			// Turn on auto complete
			$(this).autocomplete({
				source: groupNames.split(',')
			});
		}
	});
	group.append(groupLabel);
	group.append(groupInput);
	provNew.append(group);

	// Create boot method drop down
	var method = $('<div></div>');
	var methodLabel = $('<label for="method">Boot method:</label>');
	var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
	methodSelect.append('<option value="boot">boot</option>'
		+ '<option value="install">install</option>'
		+ '<option value="iscsiboot">iscsiboot</option>'
		+ '<option value="netboot">netboot</option>'
		+ '<option value="statelite">statelite</option>'
	);
	method.append(methodLabel);
	method.append(methodSelect);
	provNew.append(method);

	// Create boot type drop down
	var type = $('<div></div>');
	var typeLabel = $('<label for="type">Boot type:</label>');
	var typeSelect = $('<select id="bootType" name="bootType"></select>');
	typeSelect.append('<option value="install">pxe</option>'
		+ '<option value="iscsiboot">yaboot</option>'
		+ '<option value="zvm">zvm</option>'
	);
	type.append(typeLabel);
	type.append(typeSelect);
	provNew.append(type);

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
	provNew.append(os);

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
	provNew.append(arch);

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
	provNew.append(profile);

	/**
	 * Provision new node
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn.bind('click', function(event) {
		// TODO Insert provision code here
		openDialog('info', 'Under construction');
	});
	provNew.append(provisionBtn);

	return provNew;
}

/**
 * Create provision node division
 * 
 * @param plugin
 * 			  Plugin name to create division for
 * @param container
 *            Container to hold provisioning form
 * @return Nothing
 */
function createProvision(plugin, container){
	// Group, nodes, arch
    if ('quick' == plugin) {
        container.append(createProvWithUrl());
    } else {
        container.append(createProvNoUrl(plugin));
        container.find('#' + plugin + 'group').bind('change', function() {
            var pluginName = $(this).attr('id').replace('group', '');
            $('#' + pluginName + 'SelectNodesTable').html('<img src="images/loader.gif"></img>');
            createNodesArea($(this).val(), pluginName + 'SelectNodesTable');
        });
    }
    
    // Advanced options
    container.append('<div id="advoption"></div>');
    
    // Add provision button
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(){
        var plugin = $(this).parent().parent().attr('id').replace('ProvisionTab', '');
        quickProvision(plugin);
    });
    provisionBtn.hide();
    container.append(provisionBtn);
    
    // Bind image select to change event
    container.find('#' + plugin + 'image').bind('change', function(){
        var temp = $(this).attr('id');
        temp = temp.replace('image', '');
        $('#' + temp + 'ProvisionTab #advoption').html('<img src="images/loader.gif"></img>');
        provAdvOption($(this).val(), temp);
    });
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage',
            msg : plugin
        },

        success : function(data){
            var containerId = data.msg + 'ProvisionTab';
            var i = 0;
            var imageName = 0;
            var position = 0;
            var imageSelect = $('#' + containerId + ' #' + data.msg + 'image');
            $('#' + containerId + ' img').remove();
            if (!data.rsp.length) {
                $('#' + containerId).prepend(createWarnBar('Please run copycds and genimage in provision page before continuing!'));
                return;
            }
            
            for (i in data.rsp) {
                imageName = data.rsp[i];
                position = imageName.indexOf(' ');
                imageName = imageName.substr(0, position);
                
                imageSelect.append($('<option value="' + imageName + '">' + imageName + '</option>'));
            }
            
            // Trigger select change event
            imageSelect.trigger('change');
            // Show provision button
            $('#' + containerId + ' button').show();
        }
    });
}

/**
 * Create provision node division using URL
 * 
 * @returns Provisiong node division
 */
function createProvWithUrl(){
    var queryStr = window.location.search;
    var argArray = queryStr.substr(1).split('&');
    var tempHash = new Object();
    var i = 0;
    var tempArray;
    
    var provHtml = '';
    
    var master = '';
    var tftpserver = '';
    var nfsserver = '';    
    for (i = 0; i < argArray.length; i++) {
        tempArray = argArray[i].split('=');
        tempHash[tempArray[0]] = tempArray[1];
    }
    
    provHtml += '<div><label>Nodes:</label><input type="text" disabled="disabled" value="' + tempHash['nodes'] + '"></div>';
    provHtml += '<div><label>Architecture:</label><input type="text" disabled="disabled" value="' + tempHash['arch'] + '"></div>';
    provHtml += '<div><label>Image:</label><select id="quickimage"></select><img src="images/loader.gif"></img></div>' +
    		   '<div><label>Install NIC:</label><input value="mac"/></div>' +
    		   '<div><label>Primary NIC:</label><input value="mac"/></div>' ;
    
    if (tempHash['master']) {
    	master = tempHash['master'];
    }
    
    if (tempHash['nfsserver']) {
    	nfsserver = tempHash['nfsserver'];
    }
    
    if (tempHash['tftpserver']) {
    	tftpserver = tempHash['tftpserver'];
    }
    
    provHtml += '<div><label>xCAT master:</label><input type="text" value="' + master + '"></div>';
    provHtml += '<div><label>TFTP server:</label><input type="text" value="' + tftpserver + '"></div>';
    provHtml += '<div><label>NFS server:</label><input type="text" value="' + nfsserver + '"></div>';
    
    return provHtml;
}

/**
 * Create provision node division without using URL
 * 
 * @param plugin
 * 			  Plugin name to create division for
 * @returns {String}
 */
function createProvNoUrl(plugin){
    // Select group
    var groupHtml = '<div><label>Group:</label>';
    var groupNames = $.cookie('groups');
    if (groupNames) {
        groupHtml += '<select id="' + plugin + 'group"><option></option>';
        var temp = groupNames.split(',');
        for (var i in temp) {
            groupHtml += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
        }
        groupHtml += '</select>';
    } 
    groupHtml += '</div>';

    // Select nodes
    var nodesHtml = '<div><label>Nodes:</label><div id="' + plugin + 'SelectNodesTable" style="display: inline-block; width:700px; overflow-y:auto;">Select a group to view its nodes</div></div>';

    // Select architecture
    var archHtml = '<div><label>Architecture:</label>';
    var archName = $.cookie('osarchs');
    if (archName) {
        archHtml += '<select id="arch">';
        var temp = archName.split(',');
        for (var i in temp) {
            archHtml += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
        }
        archHtml += '</select>';
    } else {
        archHtml += '<input type="text" id="arch">';
    }
    archHtml += '</div>';

    // Add static input part
    var staticHtml = '<div><label>Image:</label><select id="' + plugin + 'image"></select><img src="images/loader.gif"></img></div>' +
    		 '<div><label>Install NIC:</label><input value="mac"/></div>' +
    		 '<div><label>Primary NIC:</label><input value="mac"/></div>' +
    		 '<div><label>xCAT Master:</label><input/></div>' +
    		 '<div><label>TFTP Server:</label><input/></div>' +
    		 '<div><label>NFS Server:</label><input/></div>';
    return groupHtml + nodesHtml + archHtml + staticHtml;
}

/**
 * Get needed fields for provsioning and send command to server 
 * 
 * @param plugin
 * 			  Plugin name of platform to provision
 * @return Nothing
 */
function quickProvision(plugin){
    var errorMessage = '';
    var argsArray = new Array();
    var nodesName = '';
    var provisionArg = '';
    var provisionFrame;
    var imageName = '';
    var url = '';
    var softwareArg = '';
    var containerId = plugin + 'ProvisionTab';
    $('#' + containerId + ' .ui-state-error').remove();
    
    $('#' + containerId + ' input[type!="checkbox"]').each(function() {
        if (!$(this).val()) {
            errorMessage = 'You are missing some inputs!';
            return false;
        } else {
            argsArray.push($(this).val());
        }
    });
    
    if (errorMessage) {
        $('#' + containerId).prepend('<p class="ui-state-error">' + errorMessage + '</p>');
        return;
    }
    
    // If jumped from nodes page, get node names 
    if ('quick' == plugin) {
        nodesName = argsArray.shift();
    }
    // Select platform, get node names from table checkbox
    else {
        // Should unshift the arch type
        argsArray.unshift($('#' + containerId + ' #arch').val());
        nodesName = getCheckedByObj($('#' + containerId + ' #' + plugin + 'SelectNodesTable'));
    }
    
    if (!nodesName) {
        $('#' + containerId).prepend('<p class="ui-state-error">Please select a node</p>');
        return;
    }
    
    softwareArg = getCheckedByObj($('#' + containerId + ' #advoption'));
    imageName = $('#' + containerId + ' #'  + plugin + 'image').val();
    provisionArg = argsArray.join(',');
    
    url = 'lib/cmd.php?cmd=webrun&tgt=&args=provision;' + nodesName + ';' + imageName + ';' + 
          provisionArg + ';' + softwareArg + '&msg=&opts=flush';
    
    // Show output
    var deployDia = $('<div id="deployDia"></div>');
    deployDia.append(createLoader()).append('<br/>');
    deployDia.append('<iframe id="provisionFrame" width="95%" height="90%" src="' + url + '"></iframe>');
    deployDia.dialog({
        modal: true,
        width: 600,
        height: 480,
        title:'Provision return',
        close: function(){$(this).remove();},
        buttons: {
            Close : function(){$(this).dialog('close');}
        }
    });

    provisionStopCheck();
}

/**
 * Create provisioning advance option
 * 
 * @param imagename
 * 			Image name
 * @param plugin
 * 			Plugin name of platform to provision
 * @return Nothing
 */
function provAdvOption(imagename, plugin) {
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage;' + imagename + ';-i;osname,provmethod',
            msg : plugin
        },

        success : function(data) {
            var containerId = data.msg + 'ProvisionTab';
            var i = 0;
            var osName = '';
            var provMethod = '';
            var tempStr = '';
            var position = 0;
            for (i = 0; i < data.rsp.length; i++) {
                tempStr = data.rsp[i];
                if (tempStr.indexOf('osname') != -1) {
                    position = tempStr.indexOf('=');
                    osName = tempStr.substr(position + 1);
                }
                
                if (tempStr.indexOf('provmethod') != -1) {
                    position = tempStr.indexOf('=');
                    provMethod = tempStr.substr(position + 1);
                }
            }
            
            $('#' + containerId + ' #advoption').empty();
            if ('aix' == osName.toLowerCase()) {
                return;
            }
            
            if ('install' == provMethod){
                $('#' + containerId + ' #advoption').html('<input type="checkbox" checked="checked" name="ganglia">Install Ganglia.');
            }
        }
    });
}

/**
 * Refresh nodes area base on group selected
 * 
 * @param groupName
 * 			Group name
 * @param areaId
 * 			Area ID to refresh
 * @return Nothing
 */
function createNodesArea(groupName, areaId) {
    // Get group nodes
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'nodels',
            tgt : groupName,
            args : '',
            msg : areaId
        },

        success : function(data) {
            var areaObj = $('#' + data.msg);
            var nodes = data.rsp;
            var index;
            var nodesHtml = '<table><thead><tr><th><input type="checkbox" onclick="selectAllCheckbox(event, $(this))"></th>';
            nodesHtml += '<th>Node</th></tr></thead><tbody>';
            for (index in nodes) {
                var node = nodes[index][0];
                if (!node) {
                    continue;
                }
                nodesHtml += '<tr><td><input type="checkbox" name="' + node + '"/></td><td>' + node + '</td></tr>';
            }
            nodesHtml += '</tbody></table>';
            
            areaObj.empty().append(nodesHtml);
            if (index > 10) {
                areaObj.css('height', '300px');
            } else {
                areaObj.css('height', 'auto');
            }
        } // End of function(data)
    });
}

function provisionStopCheck(){
    var content = $('#provisionFrame').contents().find('body').text();
    if (content.indexOf('provision stop') != -1) {
        $('#deployDia img').remove();
        clearTimeout(provisionClock);
    } else {
        provisionClock = setTimeout('provisionStopCheck()', 5000);
    }
}

/**
 * Get select element names
 * 
 * @param obj
 * 			Object to get selected element names
 * @return Nodes name seperate by a comma
 */
function getCheckedByObj(obj) {
    var str = '';
    
    // Get nodes that were checked
    obj.find('input:checked').each(function() {
        if ($(this).attr('name')) {
            str += $(this).attr('name') + ',';
        }
    });

    if (str) {
        str = str.substr(0, str.length - 1);
    }

    return str;
}
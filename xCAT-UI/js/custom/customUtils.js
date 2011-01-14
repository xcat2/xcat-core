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
    		$('#' + outId).children().remove();
    
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
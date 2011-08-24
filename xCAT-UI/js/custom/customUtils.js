/**
 * Create nodes datatable for a given group
 * 
 * @param group
 *            Group name
 * @param outId
 *            Division ID to append datatable
 * @return Nodes datatable
 */

var provisionClock;

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

function createProvision(plugin, container){
    var showStr = '';
    
  //group, nodes, arch
    if ('quick' == plugin){
        container.append(createProvWithUrl());
    }
    else{
        container.append(createProvNonurl(plugin));
        container.find('#' + plugin + 'group').bind('change', function(){
            var pluginname = $(this).attr('id').replace('group', '');
            $('#' + pluginname + 'SelectNodesTable').html('<img src="images/loader.gif"></img>');
            createNodesArea($(this).val(), pluginname + 'SelectNodesTable');
        });
    }
    
    //image,nic,master,tftp,nfs,option
    showStr = '<div><label>Image:</label><select id="' + plugin + 'image"></select><img src="images/loader.gif"></img></div>' +
            '<div><label>Install Nic:</label><input value="mac"></div>' +
            '<div><label>Primary Nic:</label><input value="mac"></div>' +
            '<div><label>xCAT Master:</label><input ></div>' +
            '<div><label>TFTP Server:</label><input ></div>' +
            '<div><label>NFS Server:</label><input ></div>' +
            '<div id="advoption"></div>';
    
    container.append(showStr);
    
    //add the provision button
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(){
        var plugin = $(this).parent().parent().attr('id').replace('ProvisionTab', '');
        quickProvision(plugin);
    });
    provisionBtn.hide();
    container.append(provisionBtn);
    
    //bind the image select change event
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
            var containerid = data.msg + 'ProvisionTab';
            var index = 0;
            var imagename = 0;
            var position = 0;
            var imageselect = $('#' + containerid + ' #' + data.msg + 'image');
            $('#' + containerid + ' img').remove();
            if (data.rsp.lenght < 1){
                $('#' + containerid).prepend(createWarnBar('Please copycds and genimage in provision page first!'));
                return;
            }
            
            for (index in data.rsp){
                imagename = data.rsp[index];
                position = imagename.indexOf(' ');
                imagename = imagename.substr(0, position);
                
                imageselect.append('<option value="' + imagename + '">' + imagename + '</option>');
            }
            //trigger the select change event
            imageselect.trigger('change');
            //show provision button
            $('#' + containerid + ' button').show();
        }
    });
}

function createProvWithUrl(){
    var querystr = window.location.search;
    var argarray = querystr.substr(1).split('&');
    var temphash = new Object();
    var index = 0;
    var temparray;
    var showstr = '';
    for (index = 0; index < argarray.length; index++){
        temparray = argarray[index].split('=');
        temphash[temparray[0]] = temparray[1];
    }
    
    showstr += '<div><label>Nodes:</label><input type="text" disabled="disabled" value="' + 
                temphash['nodes'] + '"></div>';
    showstr += '<div><label>Architecture:</label><input type="text" disabled="disabled" value="' +
                temphash['arch'] + '"></div>';
    
    return showstr;
}

function createProvNonurl(plugin){
    // Create the group area
    var strGroup = '<div><label>Group:</label>';
    var groupNames = $.cookie('groups');
    if (groupNames) {
        strGroup += '<select id="' + plugin + 'group"><option></option>';
        var temp = groupNames.split(',');
        for (var i in temp) {
            strGroup += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
        }
        strGroup += '</select>';
    } 
    strGroup += '</div>';

    // Create nodes area
    var strNodes = '<div><label>Nodes:</label><div id="' + plugin + 'SelectNodesTable" ' +
            ' style="display:inline-block;width:700px;overflow-y:auto;">Select a group to view its nodes</div></div>';

    // Create architecture
    var strArch = '<div><label>Architecture:</label>';
    var archName = $.cookie('osarchs');
    if ('' != archName) {
        strArch += '<select id="arch">';
        var temp = archName.split(',');
        for (var i in temp) {
            strArch += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
        }
        strArch += '</select>';
    } else {
        strArch += '<input type="text" id="arch">';
    }
    strArch += '</div>';

    return strGroup + strNodes + strArch;
}

/**
 * get all needed field for provsion and send the command to server 
 * 
 * @return Nothing
 */
function quickProvision(plugin){
    var errormessage = '';
    var argsArray = new Array();
    var nodesName = '';
    var provisionArg = '';
    var provisionFrame;
    var imageName = '';
    var url = '';
    var softwareArg = '';
    var containerid = plugin + 'ProvisionTab';
    $('#' + containerid + ' .ui-state-error').remove();
    
    $('#' + containerid + ' input[type!="checkbox"]').each(function(){
        if ('' == $(this).val()){
            errormessage = 'You are missing input!';
            return false;
        }
        else{
            argsArray.push($(this).val());
        }
    });
    
    if ('' != errormessage){
        $('#' + containerid).prepend('<p class="ui-state-error">' + errormessage + '</p>');
        return;
    }
    
    //if jumped from nodes page, get nodes name from input 
    if ('quick' == plugin){
        nodesName = argsArray.shift();
    }
    //select the different platform, get nodes name from table checkbox
    else{
        //should unshift the arch type
        argsArray.unshift($('#' + containerid + ' #arch').val());
        nodesName = getCheckedByObj($('#' + containerid + ' #' + plugin + 'SelectNodesTable'));
    }
    
    if ('' == nodesName){
        $('#' + containerid).prepend('<p class="ui-state-error">Please select nodes first.</p>');
        return;
    }
    
    softwareArg = getCheckedByObj($('#' + containerid + ' #advoption'));
    imageName = $('#' + containerid + ' #'  + plugin + 'image').val();
    provisionArg = argsArray.join(',');
    url = 'lib/cmd.php?cmd=webrun&tgt=&args=provision;' + nodesName + ';' + imageName + ';' + 
          provisionArg + ';' + softwareArg + '&msg=&opts=flush';
    
    // show the result
    var deployDia = $('<div id="deployDia"></div>');
    deployDia.append(createLoader()).append('<br/>');
    deployDia.append('<iframe id="provisionFrame" width="95%" height="90%" src="' + url + '"></iframe>');
    deployDia.dialog({
        modal: true,
        width: 600,
        height: 480,
        title:'Provision on Nodes',
        close: function(){$(this).remove();},
        buttons: {
            Close : function(){$(this).dialog('close');}
        }
    });

    provisionStopCheck();
}

function provAdvOption(imagename, plugin){
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage;' + imagename + ';-i;osname,provmethod',
            msg : plugin
        },

        success : function(data){
            var containerid = data.msg + 'ProvisionTab';
            var index = 0;
            var osname = '';
            var provmethod = '';
            var tempstr = '';
            var position = 0;
            for (index = 0; index < data.rsp.length; index++){
                tempstr = data.rsp[index];
                if (-1 != tempstr.indexOf('osname')){
                    position = tempstr.indexOf('=');
                    osname = tempstr.substr(position + 1);
                }
                if (-1 != tempstr.indexOf('provmethod')){
                    position = tempstr.indexOf('=');
                    provmethod = tempstr.substr(position + 1);
                }
            }
            
            $('#' + containerid + ' #advoption').empty();
            if ('aix' == osname.toLowerCase()){
                return;
            }
            
            if ('install' == provmethod){
                $('#' + containerid + ' #advoption').html('<input type="checkbox" checked="checked" name="ganglia">Install Ganglia.');
            }
        }
    });
}

/**
 * Refresh the nodes area base on group selected
 * 
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
            var showStr = '<table><thead><tr><th><input type="checkbox" onclick="selectAllCheckbox(event, $(this))"></th>';
            showStr += '<th>Node</th></tr></thead><tbody>';
            for (index in nodes) {
                var node = nodes[index][0];
                if ('' == node) {
                    continue;
                }
                showStr += '<tr><td><input type="checkbox" name="' + node + '"/></td><td>'
                        + node + '</td></tr>';
            }
            showStr += '</tbody></table>';
            areaObj.empty().append(showStr);
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
    if (-1 != content.indexOf('provision stop')){
        $('#deployDia img').remove();
        clearTimeout(provisionClock);
    }
    else{
        provisionClock = setTimeout('provisionStopCheck()', 5000);
    }
}

/**
 * Get all select elements' name in the obj
 * 
 * @return All nodes name, seperate by ','
 */
function getCheckedByObj(obj) {
    var tempStr = '';
    // Get nodes that were checked
    obj.find('input:checked').each(function() {
        if ($(this).attr('name')) {
            tempStr += $(this).attr('name') + ',';
        }
    });

    if ('' != tempStr) {
        tempStr = tempStr.substr(0, tempStr.length - 1);
    }

    return tempStr;
}
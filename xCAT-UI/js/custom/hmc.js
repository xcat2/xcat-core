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
			errorinfo = 'You are missing some inputs!';
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
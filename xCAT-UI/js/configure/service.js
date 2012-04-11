/**
 * Global variables
 */
var topPriority = 0;

/**
 * Load the service portal's provision page
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
function loadServicePage(tabId) {
	// Create info bar
	var infoBar = createInfoBar('Select a platform to configure, then click Ok.');
	
	// Create self-service portal page
	var tabId = 'serviceTab';
	var servicePg = $('<div class="form"></div>');
	$('#' + tabId).append(infoBar, servicePg);

	// Create radio buttons for platforms
	var hwList = $('<ol>Platforms available:</ol>');
	var esx = $('<li><input type="radio" name="hw" value="esx" checked/>ESX</li>');
	var kvm = $('<li><input type="radio" name="hw" value="kvm"/>KVM</li>');
	var zvm = $('<li><input type="radio" name="hw" value="zvm"/>z\/VM</li>');
	
	hwList.append(esx);
	hwList.append(kvm);
	hwList.append(zvm);
	servicePg.append(hwList);

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {		
		var configTabs = getConfigTab();
		
		// Get hardware that was selected
		var hw = $(this).parent().find('input[name="hw"]:checked').val();
	    var newTabId = hw + 'ProvisionTab';

	    if ($('#' + newTabId).size() > 0){
	    	configTabs.select(newTabId);
	    } else {
	        var title = '';
	        
	        // Create an instance of the plugin
	        var plugin;
	        switch (hw) {
	        case "kvm":
	            plugin = new kvmPlugin();
	            title = 'KVM';
	            break;
	        case "esx":
	            plugin = new esxPlugin();
	            title = 'ESX';
	            break;
	        case "zvm":
	            plugin = new zvmPlugin();
	            title = 'z/VM';
	            
	            // Get zVM host names
	        	if (!$.cookie('srv_zvm')){
	        		$.ajax( {
	        			url : 'lib/srv_cmd.php',
	        			dataType : 'json',
	        			data : {
	        				cmd : 'webportal',
	        				tgt : '',
	        				args : 'lszvm',
	        				msg : ''
	        			},

	        			success : function(data) {
	        				setzVMCookies(data);
	        			}
	        		});
	        	}
	        	
	            break;
	        }

	        // Select tab
	        configTabs.add(newTabId, title, '', true);
	        configTabs.select(newTabId);
	        plugin.loadConfigPage(newTabId);
	    }
	});
	
	servicePg.append(okBtn);
}

/**
 * Load the user panel where users can be created, modified, or deleted
 * 
 * @param panelId
 * 			Panel ID
 * @return Nothing
 */
function loadUserPanel(panelId) {
	// Get users list
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'tabdump',
			tgt : '',
			args : 'passwd',
			msg : panelId
		},

		success : loadUserTable
	});
}

/**
 * Load user datatable
 * 
 * @param data
 * 			HTTP request data
 * @return Nothing
 */
function loadUserTable(data) {
	// Get response
	var rsp = data.rsp;
	// Get panel ID
	var panelId = data.msg;
	
	// Wipe panel clean
	$('#' + panelId).empty();
	
	// Add info bar
	$('#' + panelId).append(createInfoBar('Create, edit, and delete users for the self-service portal. Double-click on a cell to edit a users properties. Click outside the table to save changes. Hit the Escape key to ignore changes.'));
	
	// Get table headers
	// The table headers in the passwd table are: key, username, password, cryptmethod, comments, and disable
	var headers = new Array('priority', 'username', 'password', 'max-vm');

	// Create a new datatable
	var tableId = 'userDatatable';
	var table = new DataTable(tableId);

	// Add column for the checkbox
	headers.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">');
	table.init(headers);
	headers.shift();

	// Append datatable to panel
	$('#' + panelId).append(table.object());

	// Add table rows
	// Start with the 2nd row (1st row is the headers)
	for ( var i = 1; i < rsp.length; i++) {
		// Split into columns
		var tmp = rsp[i].split(',');
		
		// Go through each column
		for (var j = 0; j < tmp.length; j++) {
			// Replace quote
			tmp[j] = tmp[j].replace(new RegExp('"', 'g'), '');
		}
		
		// Only add users having the key = xcat
		if (tmp[0] == 'xcat') {
			// Columns are: priority, username, password, and max-vm
			var cols = new Array('', tmp[1], tmp[2], '');
	
			// Add remove button where id = user name
			cols.unshift('<input type="checkbox" name="' + tmp[1] + '"/>');
	
			// Add row
			table.add(cols);
		}
	}

	// Turn table into datatable
	$('#' + tableId).dataTable({
		'iDisplayLength': 50,
		'bLengthChange': false,
		"sScrollX": "100%",
		"bAutoWidth": true
	});

	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');
	
	var createLnk = $('<a>Create</a>');
	createLnk.click(function() {
		openCreateUserDialog();
	});
		
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.click(function() {
		var users = getNodesChecked(tableId);
		if (users) {
			openDeleteUserDialog(users);
		}
	});
	
	var refreshLnk = $('<a>Refresh</a>');
	refreshLnk.click(function() {
		loadUserPanel(panelId);
	});
	
	// Create an action menu
	var actionsMenu = createMenu([createLnk, deleteLnk, refreshLnk]);
	actionsMenu.superfish();
	actionsMenu.css('display', 'inline-block');
	actionBar.append(actionsMenu);
	
	// Set correct theme for action menu
	actionsMenu.find('li').hover(function() {
		setMenu2Theme($(this));
	}, function() {
		setMenu2Normal($(this));
	});
	
	// Create a division to hold actions menu
	var menuDiv = $('<div id="' + tableId + '_menuDiv" class="menuDiv"></div>');
	$('#' + tableId + '_wrapper').prepend(menuDiv);
	menuDiv.append(actionBar);	
	$('#' + tableId + '_filter').appendTo(menuDiv);
			
	// Get policy data
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'tabdump',
			tgt : '',
			args : 'policy',
			msg : tableId
		},

		success : loadUserTable4Policy
	});
	
	/**
	 * Enable editable cells
	 */
	// Do not make 1st or 2nd column editable
	$('#' + tableId + ' td:not(td:nth-child(1),td:nth-child(2))').editable(
		function(value, settings) {		
		    // If users did not make changes, return the value directly
		    // jeditable saves the old value in this.revert
		    if ($(this).attr('revert') == value){
		        return value;
		    }
		    
		    var panelId = $(this).parents('.ui-accordion-content').attr('id');
		    	
			// Get column index
			var colPos = this.cellIndex;
						
			// Get row index
			var dTable = $('#' + tableId).dataTable();
			var rowPos = dTable.fnGetPosition(this.parentNode);
			
			// Update datatable
			dTable.fnUpdate(value, rowPos, colPos, false);
			
			// Get table headers
			var headers = $('#' + nodesTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
						
			// Get user attributes
			var priority = $(this).parent().find('td:eq(1)').text();
			var user = $(this).parent().find('td:eq(2)').text();
			var password = $(this).parent().find('td:eq(3)').text();
			var maxVM = $(this).parent().find('td:eq(4)').text();			
						
			// Send command to change user attributes
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'webrun',
					tgt : '',
					args : 'updateuser;' + priority + ';' + user + ';' + password + ';' + maxVM,
					msg : panelId
				},
				success : updatePanel
        	});

			return value;
		}, {
			onblur : 'submit', 	// Clicking outside editable area submits changes
			type : 'textarea',
			placeholder: ' ',
			event : "dblclick", // Double click and edit
			height : '30px' 	// The height of the text area
		});
	
	// Resize accordion
	$('#' + tableId).parents('.ui-accordion').accordion('resize');
}

/**
 * Update user datatable for policy
 * 
 * @param data
 * 			HTTP request data
 * @return Nothing
 */
function loadUserTable4Policy(data) {
	// Get response
	var rsp = data.rsp;
	// Get datatable ID
	var tableId = data.msg;
	
	// Get datatable
	var datatable = $('#' + tableId).dataTable();

	// Update max-vm column
	// The data coming back contains: priority, name, host, commands, noderange, parameters, time, rule, comments, disable
	
	// Start with the 2nd row (1st row is the headers)
	topPriority = 0;
	for ( var i = 1; i < rsp.length; i++) {
		// Split into columns
		var tmp = rsp[i].split(',');
		
		// Go through each column
		for (var j = 0; j < tmp.length; j++) {
			// Replace quote
			tmp[j] = tmp[j].replace(new RegExp('"', 'g'), '');
		}
		
		// Get the row containing the user name
		var rowPos = -1;
		if (tmp[1])
			rowPos = findRow(tmp[1], '#' + tableId, 2);
		
		// Update the priority and max-vm columns
		if (rowPos > -1) {
			var maxVM = tmp[8].replace('max-vm:', '');
			maxVM = maxVM.replace(';', '');
			datatable.fnUpdate(maxVM, rowPos, 4, false);
			
			var priority = tmp[0];
			datatable.fnUpdate(priority, rowPos, 1, false);
			
			// Set the highest priority
			if (priority > topPriority)
				topPriority = priority;
		}
	}
	
	// Adjust column sizes
	adjustColumnSize(tableId);
	
	// Resize accordion
	$('#' + tableId).parents('.ui-accordion').accordion('resize');
}

/**
 * Open a dialog to create a user
 */
function openCreateUserDialog() {
	var dialogId = 'createUser';
	var dialog = $('<div id="' + dialogId + '" class="form"></div>');
    var info = createInfoBar('Create an xCAT user. A priority will be generated for the new user.');
    dialog.append(info);
    
    // Generate the user priority
    var userPriority = parseFloat(topPriority) + 0.01;
    userPriority = userPriority.toPrecision(3);
    
    // Create node inputs
    dialog.append($('<div><label>Priority:</label><input name="priority" type="text" disabled="disabled" value="' + userPriority + '"></div>'));
	dialog.append($('<div><label>User name:</label><input name="username" type="text"></div>'));
	dialog.append($('<div><label>Password:</label><input name="password" type="password"></div>'));
	dialog.append($('<div><label>Maximum virtual machines:</label><input name="maxvm" type="text"></div>'));
    
    dialog.dialog({
    	title: 'Create user',
        modal: true,
        width: 400,
        close: function(){
        	$(this).remove();
        },
        buttons: {
            "OK" : function(){
            	// Remove any warning messages
        		$(this).find('.ui-state-error').remove();
        		
        		// Change dialog buttons
			    $('#' + dialogId).dialog('option', 'buttons', {
			    	'Close':function(){
			    		$(this).dialog('close');
			    	}
			    });
        		
        		var priority = $(this).find('input[name="priority"]').val();
            	var user = $(this).find('input[name="username"]').val();
            	var password = $(this).find('input[name="password"]').val();
            	var maxVM = $(this).find('input[name="maxvm"]').val();
            	
            	// Verify inputs are provided
            	if (!user || !password || !maxVM) {
            		var warn = createWarnBar('Please provide a value for each missing field!');
					warn.prependTo($(this));
            	} else {            	
            		$.ajax( {
        				url : 'lib/cmd.php',
        				dataType : 'json',
        				data : {
        					cmd : 'webrun',
        					tgt : '',
        					args : 'updateuser;' + priority + ';' + user + ';' + password + ';' + maxVM,
        					msg : dialogId
	    				},
	    				success : updatePanel
	            	});
            		
            		// Update highest priority
            		topPriority = priority;
            	}
            },
            "Cancel": function(){
            	$(this).dialog('close');
            }
        }
    });
}

/**
 * Update dialog
 * 
 * @param data
 * 			HTTP request data
 * @return Nothing
 */
function updatePanel(data) {
	var dialogId = data.msg;
	var infoMsg;

	// Create info message
	if (jQuery.isArray(data.rsp)) {
		infoMsg = '';
		for (var i in data.rsp) {
			infoMsg += data.rsp[i] + '</br>';
		}
	} else {
		infoMsg = data.rsp;
	}
	
	// Create info bar with close button
	var infoBar = $('<div class="ui-state-highlight ui-corner-all"></div>').css('margin', '5px 0px');
	var icon = $('<span class="ui-icon ui-icon-info"></span>').css({
		'display': 'inline-block',
		'margin': '10px 5px'
	});
	
	// Create close button to close info bar
	var close = $('<span class="ui-icon ui-icon-close"></span>').css({
		'display': 'inline-block',
		'float': 'right'
	}).click(function() {
		$(this).parent().remove();
	});
	
	var msg = $('<pre>' + infoMsg + '</pre>').css({
		'display': 'inline-block',
		'width': '85%'
	});
	
	infoBar.append(icon, msg, close);	
	infoBar.prependTo($('#' + dialogId));
}

/**
 * Open dialog to confirm user delete
 * 
 * @param users
 * 			Users to delete
 * @return Nothing
 */
function openDeleteUserDialog(users) {
	// Create form to delete disk to pool
	var dialogId = 'deleteUser';
	var deleteForm = $('<div id="' + dialogId + '" class="form"></div>');
	
	// Create info bar
	var info = createInfoBar('Are you sure you want to delete ' + users.replace(new RegExp(',', 'g'), ', ') + '?');
	deleteForm.append(info);
			
	// Open dialog to delete user
	deleteForm.dialog({
		title:'Delete user',
		modal: true,
		width: 400,
		close: function(){
        	$(this).remove();
        },
		buttons: {
        	"Ok": function(){
        		// Remove any warning messages
        		$(this).find('.ui-state-error').remove();
        		
				// Change dialog buttons
				$(this).dialog('option', 'buttons', {
					'Close': function() {$(this).dialog("close");}
				});
										
				// Delete user
				$.ajax( {
    				url : 'lib/cmd.php',
    				dataType : 'json',
    				data : {
    					cmd : 'webrun',
    					tgt : '',
    					args : 'deleteuser;' + users,
    					msg : dialogId
    				},
    				success : updatePanel
            	});
			},
			"Cancel": function() {
        		$(this).dialog( "close" );
        	}
		}
	});
}

/**
 * Round a floating point to a given precision
 * 
 * @param value
 * 			Floating point
 * @param precision
 * 			Decimal precision
 * @returns	Floating point number
 */
function toFixed(value, precision) {
    var power = Math.pow(10, precision || 0);
    return String(Math.round(value * power) / power);
}
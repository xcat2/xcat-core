/**
 * Global variables
 */
var userDatatable;
var topPriority = 0;
var tableId = 'usersTable';

/**
 * Get user access table 
 * 
 * @returns User access table
 */
function getUsersTable(){
    return userDatatable;
}

/**
 * Set user access table
 * 
 * @param table User access table
 */
function setUsersTable(table){
    userDatatable = table;
}

/**
 * Load the user page
 */
function loadUserPage() {
	// Retrieve users from policy table
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'policy',
            msg : ''
        },

        success : loadUserTable
    });
}

/**
 * Load user table
 * 
 * @param data Data returned from HTTP request 
 */
function loadUserTable(data){
    var tabId = 'usersTab';
        
    $('#' + tabId).empty();
    
    // Set padding for page
    $('#' + tabId).css('padding', '20px 60px');
    
    // Create info bar
    var info = $('#' + tabId).find('.ui-state-highlight');
    // If there is no info bar
    if (!info.length) {
        var infoBar = createInfoBar('Configure access given to users.');
        
        // Create users page
        var userPg = $('<div class="form"></div>');
        $('#' + tabId).append(infoBar, userPg);
    }

    if (data.rsp) {
    	// Create a datatable if one does not exist 
        var table = new DataTable(tableId);
        var headers = new Array('Priority', 'Name', 'Host', 'Commands', 'Noderange', 'Parameters', 'Time', 'Rule', 'Comments', 'Disable');
        
        // Add column for the checkbox
        headers.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">');
        table.init(headers);
        headers.shift();
        
        // Append datatable to panel
        $('#' + tabId).append(table.object());
        
        topPriority = 0;
        
        // Add table rows
        // Start with the 2nd row (1st row is the headers)
        for (var i = 1; i < data.rsp.length; i++) {
            // Split into columns
            var cols = data.rsp[i].split(',');

            // Go through each column
            for (var j = 0; j < cols.length; j++) {

                // If the column is not complete
                if (cols[j].count('"') == 1) {
                    while (cols[j].count('"') != 2) {
                        // Merge this column with the adjacent one
                        cols[j] = cols[j] + "," + cols[j + 1];

                        // Remove merged row
                        cols.splice(j + 1, 1);
                    }
                }

                // Replace quote
                cols[j] = cols[j].replace(new RegExp('"', 'g'), '');
            }
            
            // Set the highest priority
            priority = cols[0];
            if (priority > topPriority)
                topPriority = priority;

            // Add check box where name = user name
            cols.unshift('<input type="checkbox" name="' + cols[0] + '"/>');

            // Add row
            table.add(cols);
        }
        
        // Turn table into datatable
        var dTable = $('#' + tableId).dataTable({        
            'iDisplayLength': 50,
            'bLengthChange': false,
            "bScrollCollapse": true,
            "sScrollY": "400px",
            "sScrollX": "100%",
            "bAutoWidth": true,
            "oLanguage": {
                "oPaginate": {
                  "sNext": "",
                  "sPrevious": ""
                }
            }
        });
        setUsersTable(dTable);  // Cache user access table
    }
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>').css("width", "450px");
    
    var createLnk = $('<a>Create</a>');
    createLnk.click(function() {
    	openCreateUserDialog("");
    });
    
    var editLnk = $('<a>Edit</a>');
    editLnk.click(function() {
    	// Should only allow 1 user to be edited at a time
        var users = getNodesChecked(tableId).split(',')
        for (var i in users) {
        	openCreateUserDialog(users[i]);
        }
    });
        
    var deleteLnk = $('<a>Delete</a>');
    deleteLnk.click(function() {
    	// Find the user name from datatable
    	var usersList = "";
        var users = $('#' + tableId + ' input[type=checkbox]:checked');
        for (var i in users) {
            var user = users.eq(i).parents('tr').find('td:eq(2)').text();
            if (user && user != "undefined") {
            	usersList += user;
                if (i < users.length - 1) {
                	usersList += ',';
                }
            }
        }
        
        if (usersList) {
        	openDeleteUserDialog(usersList);
        }
    });
    
    var refreshLnk = $('<a>Refresh</a>');
    refreshLnk.click(function() {
    	loadUserPage();
    });
    
    // Create an action menu
    var actionsMenu = createMenu([refreshLnk, createLnk, editLnk, deleteLnk]);
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
}

/**
 * Open create user dialog
 * 
 * @param data User data (only during edit)
 */
function openCreateUserDialog(data) {
    var dialogId = 'createUser';
    
    // Generate the user priority
    var priority = parseFloat(topPriority) + 0.01;
    priority = priority.toPrecision(3);
    
    // Create form to create user
    var createUserForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Create a user and configure access to xCAT.');
    
    var userFS = $('<fieldset></fieldset>');
    var userLegend = $('<legend>User</legend>');
    userFS.append(userLegend);
    
    var userAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    userFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/nodes/users.png"></img></div>'));
    userFS.append(userAttr);
    
    var optionFS = $('<fieldset></fieldset>');
    var optionLegend = $('<legend>Options</legend>');
    optionFS.append(optionLegend);
    
    var optionAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    optionFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>'));
    optionFS.append(optionAttr);
    
    createUserForm.append(info, userFS, optionFS);
    
    userAttr.append($('<div><label>Priority:</label><input type="text" name="priority" disabled="disabled" value="' + priority + '" title="The priority value for this user"/></div>'));
    userAttr.append($('<div><label>User name:</label><input type="text" name="name" title="The user name to log into xCAT with"/></div>'));
    var type = $('<div><label>Type:</label></div>');
    var typeSelect = $('<select name="user_type" title="Specifies the type of user.">' +
    		'<option value="guest">Guest</option>' +
    		'<option value="admin">Administrator</option>' +    		
		'</select>');
    type.append(typeSelect);    
    userAttr.append(type);
    userAttr.append($('<div><label>Password:</label><input name="password" type="password" title="The user password that will be used to log into xCAT"></div>'));
    userAttr.append($('<div><label>Confirm password:</label><input name="confirm_password" type="password" title="The user password that will be used to log into xCAT"></div>'));
    
    optionAttr.append($('<div><label>Host:</label><input type="text" name="host" title="The host from which users may issue the commands specified by this rule. By default, it is all hosts."/></div>'));
    optionAttr.append($('<div><label>Commands:</label><input type="text" name="commands" title="The list of commands that this rule applies to. By default, it is all commands."/></div>'));
    optionAttr.append($('<div><label>Parameters:</label><input type="text" name="parameters" title="A regular expression that matches the command parameters (everything except the noderange) that this rule applies to. By default, it is all parameters."/></div>'));
    optionAttr.append($('<div><label>Node Range:</label><input type="text" name="nodeRange" title="The node range that this rule applies to. By default, it is all nodes."/></div>'));
    optionAttr.append($('<div><label>Rule:</label><select name="rule" title="Specifies how this rule should be applied. Valid values are: allow, accept, trusted, and deny.">' +
    		'<option value="allow">Allow</option>' +
    		'<option value="accept">Accept</option>' +
    		'<option value="trusted">Trusted</option>' +
    		'<option value="deny">Deny</option>' + 
		'</select></div>'));
    
    optionAttr.append($('<div><label>Comments:</label><input type="text" name="comments" style="width: 250px;" title="Any user written notes"/></div>'));
    optionAttr.append($('<div><label>Disable:</label><select name="disable" title="Set to yes to disable the user">' + 
    		'<option value="">No</option>' + 
    		'<option value="yes">Yes</option>' +
		'</select></div>'));
    
	// Generate tooltips
    createUserForm.find('div input[title],select[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.8,
        delay: 0,
        predelay: 800,
        events: {
              def:     "mouseover,mouseout",
              input:   "mouseover,mouseout",
              widget:  "focus mouseover,blur mouseout",
              tooltip: "mouseover,mouseout"
        },

        // Change z index to show tooltip in front
        onBeforeShow: function() {
            this.getTip().css('z-index', $.topZIndex());
        }
    });
    
    // Open dialog to add disk
    createUserForm.dialog({
        title:'Configure user',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 600,
        buttons: {
            "Ok": function(){
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get inputs
                var priority = $(this).find('input[name=priority]').val();
                var usrName = $(this).find('input[name=name]').val();
                var password = $(this).find('input[name=password]').val();
                var confirmPassword = $(this).find('input[name=confirm_password]').val();
                var host = $(this).find('input[name=host]').val();
                var commands = $(this).find('input[name=commands]').val();
                var parameters = $(this).find('input[name=parameters]').val();
                var nodeRange = $(this).find('input[name=nodeRange]').val();
                var rule = $(this).find('select[name=rule]').val();
                var comments = $(this).find('input[name=comments]').val();
                var disable = $(this).find('select[name=disable]').val();
                
                // Verify user name and passwords are supplied
                if (!usrName) {
                    var warn = createWarnBar('Please provide a user name');
                    warn.prependTo($(this));
                    return;
                }
                
                // Verify passwords match
                if (password != confirmPassword) {
                	var warn = createWarnBar('Passwords do not match');
                    warn.prependTo($(this));
                    return;
                }

                var args = "";
                if (usrName) {
                    args += ' policy.name=' + usrName;
                } if (rule) {
                    args += ' policy.rule=' + rule;
                } if (disable) {
                    args += ' policy.disable=' + disable;
                }
                
                // Handle cases where there are value or no value
                if (host) {
                    args += " policy.host='" + host + "'";
                } else {
                	args += " policy.host=''";
                }
                
                if (parameters) {
                    args += " policy.parameters='" + parameters + "'";
                } else {
                	args += " policy.parameters=''";
                }
                
                if (nodeRange) {
                    args += " policy.noderange='" + nodeRange + "'";
                } else {
                	args += " policy.noderange=''";
                }

                if (comments) {
                    args += " policy.comments='" + comments + "'";
                } else {
                	args += " policy.comments=''";
                }
                
                if (commands) {
                    args += " policy.commands='" + commands + "'";
                } else {
                	args += " policy.commands=''";
                }
                
                // Trim any extra spaces
                args = jQuery.trim(args);  
                
                // Change dialog buttons
                $(this).dialog('option', 'buttons', {
                    'Close': function() {$(this).dialog("close");}
                });

                // Submit request to update policy and passwd tables                
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'policy||' + priority + '||' + args,
                        msg : dialogId
                    },
                    
                    success : updatePanel
                });

                if (password) {
	                $.ajax({
	                    url : 'lib/cmd.php',
	                    dataType : 'json',
	                    data : {
	                        cmd : 'webrun',
	                        tgt : '',
	                        args : 'passwd||' + usrName + '||' + password,
	                        msg : dialogId
	                    },
	                    
	                    success : updatePanel
	                });
                }
                                
                // Update highest priority
                topPriority = priority;
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
    
    // Change comments if access checkbox is checked
    typeSelect.change(function() {
    	var comments = createUserForm.find('input[name=comments]').val();
    	var cmds = createUserForm.find('input[name=commands]').val();
    	comments = jQuery.trim(comments);
    	cmds = jQuery.trim(cmds);
    	
    	var tag = "privilege:root";
    	
    	// The list of every command used by the self-service page
    	// Every command must be separated by a comma
    	var authorizedCmds = "authcheck,lsdef,nodestat,tabdump,rinv,rpower,rmvm,webportal,webrun";
    	
    	// Append tag to commands and comments
    	if (typeSelect.val().indexOf("admin") > -1) {  		
    		if (comments && comments.charAt(comments.length - 1) != ";") {
    			comments += ";";
    		}
    		
    		comments += tag;
    		createUserForm.find('input[name=comments]').val(comments);    		
    		createUserForm.find('input[name=commands]').val("");
    	} else {
    		comments = comments.replace(tag, "");
    		comments = comments.replace(";;", ";");
    		createUserForm.find('input[name=comments]').val(comments);    		
    		createUserForm.find('input[name=commands]').val(authorizedCmds);
    	}
    	
    	// Strip off leading semi-colon
    	if (comments.charAt(0) == ";") {
    		comments = comments.substr(1, comments.length);
    		createUserForm.find('input[name=comments]').val(comments);
    	}
	});
    
    // Set the user data (on edit)
    if (data) {
    	var checkBox = $('#' + tableId + ' input[name="' + data + '"]');
    	
    	var priority = data;
        var name = checkBox.parents('tr').find('td:eq(2)').text();
        var host = checkBox.parents('tr').find('td:eq(3)').text();
        var commands = checkBox.parents('tr').find('td:eq(4)').text();
        var noderange = checkBox.parents('tr').find('td:eq(5)').text();
        var parameters = checkBox.parents('tr').find('td:eq(6)').text();
        var time = checkBox.parents('tr').find('td:eq(7)').text();
        var rule = checkBox.parents('tr').find('td:eq(8)').text();
        var comments = checkBox.parents('tr').find('td:eq(9)').text();
        var disable = checkBox.parents('tr').find('td:eq(10)').text();
        
        createUserForm.find('input[name=priority]').val(priority);
        createUserForm.find('input[name=name]').val(name);
        
        // Do not show password (security)
        createUserForm.find('input[name=password]').val();
        createUserForm.find('input[name=confirm_password]').val();
        
        createUserForm.find('input[name=host]').val(host);
        createUserForm.find('input[name=commands]').val(commands);
        createUserForm.find('input[name=parameters]').val(parameters);
        createUserForm.find('input[name=nodeRange]').val(noderange);
        createUserForm.find('select[name=rule]').val(rule);
        createUserForm.find('input[name=comments]').val(comments);
        createUserForm.find('select[name=disable]').val(disable);
        
        if (comments.indexOf("privilege:root") > -1) {
        	typeSelect.val("admin");
        }
    } else {
    	// Default user type to guest
    	typeSelect.val("guest").change();
    }
}
/**
 * Open dialog to confirm user delete
 * 
 * @param users Users to delete
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
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'deleteuser||' + users,
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
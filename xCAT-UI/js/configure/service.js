/**
 * Global variables
 */
var topPriority = 0;

/**
 * Load the service portal's provision page
 * 
 * @param tabId Tab ID where page will reside
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
            var plugin = null;
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
 * @param panelId Panel ID
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
 * @param data HTTP request data
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
    var tableId = panelId + 'Datatable';
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
            onblur : 'submit',  // Clicking outside editable area submits changes
            type : 'textarea',
            placeholder: ' ',
            event : "dblclick", // Double click and edit
            height : '30px'     // The height of the text area
        });
    
    // Resize accordion
    $('#' + tableId).parents('.ui-accordion').accordion('resize');
}

/**
 * Update user datatable for policy
 * 
 * @param data HTTP request data
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
 * @param data HTTP request data
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
 * @param value Floating point
 * @param precision Decimal precision
 * @returns Floating point number
 */
function toFixed(value, precision) {
    var power = Math.pow(10, precision || 0);
    return String(Math.round(value * power) / power);
}

/**
 * Query the images that exists
 * 
 * @param panelId Panel ID
 */
function queryImages(panelId) {
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'osimage',
            msg : panelId
        },

        success : configImagePanel
    });
}

/**
 * Panel to configure OS images
 * 
 * @param data Data from HTTP request
 */
function configImagePanel(data) {    
    var panelId = data.msg;
    var rsp = data.rsp;
    
    // Wipe panel clean
    $('#' + panelId).empty();

    // Add info bar
    $('#' + panelId).append(createInfoBar('Create, edit, and delete operating system images for the self-service portal.'));
    
    // Create table
    var tableId = panelId + 'Datatable';
    var table = new DataTable(tableId);
    table.init(['<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'Name', 'Selectable', 'OS Version', 'OS Arch', 'OS Name', 'Type', 'Profile', 'Method', 'Description']);

    // Insert images into table
    var imagePos = 0;
    var profilePos = 0;
    var osversPos = 0;
    var osarchPos = 0;
    var osnamePos = 0;
    var imagetypePos = 0;
    var provMethodPos = 0;
    var comments = 0;
    var desc, selectable, tmp;
    // Get column index for each attribute
    var colNameArray = rsp[0].substr(1).split(',');
    for (var i in colNameArray){
        switch (colNameArray[i]){
            case 'imagename': {
                imagePos = i;
            }
            break;
            
            case 'profile':{
                profilePos = i;
            }
            break;
            
            case 'osvers':{
                osversPos = i;
            }
            break;
            
            case 'osarch':{
                osarchPos = i;
            }
            break;
            
            case 'osname':{
                osnamePos = i;
            }
            break;
            
            case 'imagetype':{
                imagetypePos = i;
            }
            break;
            
            case 'comments':{
                comments = i;
            }
            break;
            
            case 'provmethod':{
                provMethodPos = i;
            }            
            break;
            
            default :
            break;
        }
    }
    
    // Go through each index
    for (var i = 1; i < rsp.length; i++) {
        // Get image name
        var cols = rsp[i].split(',');
        var name = cols[imagePos].replace(new RegExp('"', 'g'), '');
        var profile = cols[profilePos].replace(new RegExp('"', 'g'), '');
        var provMethod = cols[provMethodPos].replace(new RegExp('"', 'g'), '');
        var osVer = cols[osversPos].replace(new RegExp('"', 'g'), '');
        var osArch = cols[osarchPos].replace(new RegExp('"', 'g'), '');
        var osName = cols[osnamePos].replace(new RegExp('"', 'g'), '');
        var imageType = cols[imagetypePos].replace(new RegExp('"', 'g'), '');
        var osComments = cols[comments].replace(new RegExp('"', 'g'), '');
                
        // Only save install boot and s390x architectures
        if (osArch == "s390x") {
            // Set default description and selectable
            selectable = "no";
            desc = "No description";
            
            if (osComments) {
                tmp = osComments.split('|');
                for (var j = 0; j < tmp.length; j++) {
                    // Save description
                    if (tmp[j].indexOf('description:') > -1) {
                        desc = tmp[j].replace('description:', '');
                        desc = jQuery.trim(desc);
                    }
                    
                    // Is the image selectable?
                    if (tmp[j].indexOf('selectable:') > -1) {
                        selectable = tmp[j].replace('selectable:', '');
                        selectable = jQuery.trim(selectable);
                    }
                }
            }
            
            // Columns are: name, selectable, OS version, OS arch, OS name, type, profile, method, and description
            var cols = new Array(name, selectable, osVer, osArch, osName, imageType, profile, provMethod, desc);

            // Add remove button where id = user name
            cols.unshift('<input type="checkbox" name="' + name + '"/>');

            // Add row
            table.add(cols);
        }        
    }
    
    // Append datatable to tab
    $('#' + panelId).append(table.object());

    // Turn into datatable
    $('#' + tableId).dataTable({
        'iDisplayLength': 50,
        'bLengthChange': false,
        "sScrollX": "100%",
        "bAutoWidth": true
    });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>');
    
    // Create a profile
    var createLnk = $('<a>Create</a>');
    createLnk.click(function() {
        imageDialog();
    });
    
    // Edit a profile
    var editLnk = $('<a>Edit</a>');
    editLnk.click(function() {
        var images = $('#' + tableId + ' input[type=checkbox]:checked');
        for (var i in images) {
            var image = images.eq(i).attr('name');            
            if (image) {
                // Columns are: name, selectable, OS version, OS arch, OS name, type, profile, method, and description
                var cols = images.eq(i).parents('tr').find('td');
                var selectable = cols.eq(2).text();                
                var osVersion = cols.eq(3).text();
                var osArch = cols.eq(4).text();
                var osName = cols.eq(5).text();
                var type = cols.eq(6).text();
                var profile = cols.eq(7).text();
                var method = cols.eq(8).text();
                var description = cols.eq(9).text();
                
                editImageDialog(image, selectable, osVersion, osArch, osName, type, profile, method, description);
            }
        }
    });
        
    // Delete a profile
    var deleteLnk = $('<a>Delete</a>');
    deleteLnk.click(function() {
        var images = getNodesChecked(tableId);
        if (images) {
            deleteImageDialog(images);
        }
    });
    
    // Refresh profiles table
    var refreshLnk = $('<a>Refresh</a>');
    refreshLnk.click(function() {
        queryImages(panelId);
    });
    
    // Create an action menu
    var actionsMenu = createMenu([createLnk, editLnk, deleteLnk, refreshLnk]);
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

    // Resize accordion
    $('#' + tableId).parents('.ui-accordion').accordion('resize');
}

/**
 * Open image dialog
 */
function imageDialog() {
    // Create form to add profile
    var dialogId = 'createImage';
    var imageForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the image. The image name will be generated based on the attributes you will give.');
    imageForm.append(info);
        
    var imageName = $('<div><label>Image name:</label><input type="text" name="imagename" disabled="disabled"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable"/></div>');
    var imageType = $('<div><label>Image type:</label><input type="text" name="imagetype" value="linux"/></div>');
    var architecture = $('<div><label>OS architecture:</label><input type="text" name="osarch"/></div>');
    var osName = $('<div><label>OS name:</label><input type="text" name="osname" value="Linux"/></div>');
    var osVersion = $('<div><label>OS version:</label><input type="text" name="osvers"/></div>');    
    var profile = $('<div><label>Profile:</label><input type="text" name="profile"/></div>');
    var provisionMethod = $('<div><label>Provision method:</label></div>');
    var provisionSelect = $('<select name="provmethod">'
            + '<option value=""></option>'
            + '<option value="install">install</option>'
            + '<option value="netboot">netboot</option>'
            + '<option value="statelite">statelite</option>'
        + '</select>');
    provisionMethod.append(provisionSelect);
    var comments = $('<div><label>Description:</label><input type="text" name="comments"/></div>');
    imageForm.append(imageName, selectable, imageType, architecture, osName, osVersion, profile, provisionMethod, comments);
    
    // Open dialog to add image
    imageForm.dialog({
        title:'Create image',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 400,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get image attributes
                var imageType = $(this).find('input[name="imagetype"]');
                var selectable = $(this).find('input[name="selectable"]');
                var architecture = $(this).find('input[name="osarch"]');
                var osName = $(this).find('input[name="osname"]');
                var osVersion = $(this).find('input[name="osvers"]');
                var profile = $(this).find('input[name="profile"]');
                var provisionMethod = $(this).find('select[name="provmethod"]');
                var comments = $(this).find('input[name="comments"]');
                                
                // Check that image attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(imageType, architecture, osName, osVersion, profile, provisionMethod);
                for (var i in inputs) {
                    if (!inputs[i].val()) {
                        inputs[i].css('border-color', 'red');
                        ready = 0;
                    } else
                        inputs[i].css('border-color', '');
                }
                
                // If inputs are not complete, show warning message
                if (!ready) {
                    var warn = createWarnBar('Please provide a value for each missing field.');
                    warn.prependTo($(this));
                } else {
                    // Override image name
                    $(this).find('input[name="imagename"]').val(osVersion.val() + '-' + architecture.val() + '-' + provisionMethod.val() + '-' + profile.val());
                    var imageName = $(this).find('input[name="imagename"]');
                    
                    // Change dialog buttons
                    $(this).dialog('option', 'buttons', {
                        'Close': function() {$(this).dialog("close");}
                    });
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = 'updateosimage;' + imageName.val() + ';' +
                        imageType.val() + ';' +
                        architecture.val() + ';' +
                        osName.val() + ';' +
                        osVersion.val() + ';' +
                        profile.val() + ';' +
                        provisionMethod.val() + ';';
                        
                    if (selectable.attr('checked'))
                        args += '"description:' + comments.val() + '|selectable:yes"';
                    else
                        args += '"description:' + comments.val() + '|selectable:no"';
                                                            
                    // Add image to xCAT
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : args,
                            msg : dialogId
                        },
    
                        success : updatePanel
                    });
                }
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Edit image dialog
 * 
 * @param iName Image name
 * @param iSelectable Is image selectable from service page
 * @param iOsVersion OS version
 * @param iProfile Profile name
 * @param iMethod Provisioning method
 * @param iComments Image description
 */
function editImageDialog(iName, iSelectable, iOsVersion, iOsArch, iOsName, iType, iProfile, iMethod, iComments) {
    // Create form to add profile
    var dialogId = 'editImage';
    var imageForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the image. The image name will be generated based on the attributes you will give.');
    imageForm.append(info);
        
    var imageName = $('<div><label>Image name:</label><input type="text" name="imagename" disabled="disabled"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable"/></div>');
    var imageType = $('<div><label>Image type:</label><input type="text" name="imagetype" value="linux"/></div>');
    var architecture = $('<div><label>OS architecture:</label><input type="text" name="osarch"/></div>');
    var osName = $('<div><label>OS name:</label><input type="text" name="osname"/></div>');
    var osVersion = $('<div><label>OS version:</label><input type="text" name="osvers"/></div>');    
    var profile = $('<div><label>Profile:</label><input type="text" name="profile"/></div>');
    var provisionMethod = $('<div><label>Provision method:</label></div>');
    var provisionSelect = $('<select name="provmethod">'
            + '<option value=""></option>'
            + '<option value="install">install</option>'
            + '<option value="netboot">netboot</option>'
            + '<option value="statelite">statelite</option>'
        + '</select>');
    provisionMethod.append(provisionSelect);
    var comments = $('<div><label>Description:</label><input type="text" name="comments"/></div>');
    imageForm.append(imageName, selectable, imageType, architecture, osName, osVersion, profile, provisionMethod, comments);
    
    // Fill in image attributes
    imageForm.find('input[name="imagename"]').val(iName);
    imageForm.find('input[name="osvers"]').val(iOsVersion);
    imageForm.find('input[name="osarch"]').val(iOsArch);
    imageForm.find('input[name="osname"]').val(iOsName);
    imageForm.find('input[name="imagetype"]').val(iType);
    imageForm.find('input[name="profile"]').val(iProfile);
    imageForm.find('select[name="provmethod"]').val(iMethod);
    imageForm.find('input[name="comments"]').val(iComments);
    if (iSelectable == "yes")
        imageForm.find('input[name="selectable"]').attr('checked', 'checked');
        
    // Open dialog to add image
    imageForm.dialog({
        title:'Edit image',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 400,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get image attributes
                var imageType = $(this).find('input[name="imagetype"]');
                var selectable = $(this).find('input[name="selectable"]');
                var architecture = $(this).find('input[name="osarch"]');
                var osName = $(this).find('input[name="osname"]');
                var osVersion = $(this).find('input[name="osvers"]');
                var profile = $(this).find('input[name="profile"]');
                var provisionMethod = $(this).find('select[name="provmethod"]');
                var comments = $(this).find('input[name="comments"]');
                                
                // Check that image attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(imageType, architecture, osName, osVersion, profile, provisionMethod);
                for (var i in inputs) {
                    if (!inputs[i].val()) {
                        inputs[i].css('border-color', 'red');
                        ready = 0;
                    } else
                        inputs[i].css('border-color', '');
                }
                
                // If inputs are not complete, show warning message
                if (!ready) {
                    var warn = createWarnBar('Please provide a value for each missing field.');
                    warn.prependTo($(this));
                } else {
                    // Override image name
                    $(this).find('input[name="imagename"]').val(osVersion.val() + '-' + architecture.val() + '-' + provisionMethod.val() + '-' + profile.val());
                    var imageName = $(this).find('input[name="imagename"]');
                    
                    // Change dialog buttons
                    $(this).dialog('option', 'buttons', {
                        'Close': function() {$(this).dialog("close");}
                    });
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = 'updateosimage;' + imageName.val() + ';' +
                        imageType.val() + ';' +
                        architecture.val() + ';' +
                        osName.val() + ';' +
                        osVersion.val() + ';' +
                        profile.val() + ';' +
                        provisionMethod.val() + ';';
                        
                    if (selectable.attr('checked'))
                        args += '"description:' + comments.val() + '|selectable:yes"';
                    else
                        args += '"description:' + comments.val() + '|selectable:no"';
                                                            
                    // Add image to xCAT
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : args,
                            msg : dialogId
                        },
    
                        success : updatePanel
                    });
                }
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Open dialog to confirm image delete
 * 
 * @param images Images to delete
 */
function deleteImageDialog(images) {
    // Create form to delete disk to pool
    var dialogId = 'deleteImage';
    var deleteForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Are you sure you want to delete ' + images.replace(new RegExp(',', 'g'), ', ') + '?');
    deleteForm.append(info);
            
    // Open dialog to delete user
    deleteForm.dialog({
        title:'Delete image',
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
                        args : 'rmosimage;' + images,
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
 * Query the groups that exists
 * 
 * @param panelId Panel ID
 */
function queryGroups(panelId) {
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'hosts',
            msg : panelId
        },

        success : configGroupPanel
    });
}

/**
 * Panel to configure groups
 * 
 * @param data Data from HTTP request
 */
function configGroupPanel(data) {    
    var panelId = data.msg;
    var rsp = data.rsp;
    
    // Wipe panel clean
    $('#' + panelId).empty();

    // Add info bar
    $('#' + panelId).append(createInfoBar('Create, edit, and delete groups for the self-service portal.'));
    
    // Create table
    var tableId = panelId + 'Datatable';
    var table = new DataTable(tableId);
    table.init(['<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'Name', 'Selectable', 'IP', 'Hostname', 'Network', 'Description']);

    // Insert groups into table
    var nodePos = 0;
    var ipPos = 0;
    var hostnamePos = 0;
    var commentsPos = 0;
    var desc, selectable, tmp;
    // Get column index for each attribute
    var colNameArray = rsp[0].substr(1).split(',');
    for (var i in colNameArray){
        switch (colNameArray[i]){
            case 'node':
                nodePos = i;
                break;
            
            case 'ip':
                ipPos = i;
                break;
            
            case 'hostnames':
                hostnamePos = i;
                break;
            
            case 'comments':
                commentsPos = i;
                break;
            
            default :
                break;
        }
    }
    
    // Go through each index
    for (var i = 1; i < rsp.length; i++) {
        // Get image name
        var cols = rsp[i].split(',');
        var name = cols[nodePos].replace(new RegExp('"', 'g'), '');
        var ip = cols[ipPos].replace(new RegExp('"', 'g'), '');
        var hostname = cols[hostnamePos].replace(new RegExp('"', 'g'), '');
        var comments = cols[commentsPos].replace(new RegExp('"', 'g'), '');
                
        // Set default description and selectable
        selectable = "no";
        network = "";
        desc = "No description";
        
        if (comments) {
            tmp = comments.split('|');
            for (var j = 0; j < tmp.length; j++) {
                // Save description
                if (tmp[j].indexOf('description:') > -1) {
                    desc = tmp[j].replace('description:', '');
                    desc = jQuery.trim(desc);
                }
                
                // Save network
                if (tmp[j].indexOf('network:') > -1) {
                    network = tmp[j].replace('network:', '');
                    network = jQuery.trim(network);
                }
                
                // Is the group selectable?
                if (tmp[j].indexOf('selectable:') > -1) {
                    selectable = tmp[j].replace('selectable:', '');
                    selectable = jQuery.trim(selectable);
                }
            }
        }
        
        // Columns are: name, selectable, network, and description
        var cols = new Array(name, selectable, ip, hostname, network, desc);

        // Add remove button where id = user name
        cols.unshift('<input type="checkbox" name="' + name + '"/>');

        // Add row
        table.add(cols);
    }
    
    // Append datatable to tab
    $('#' + panelId).append(table.object());

    // Turn into datatable
    $('#' + tableId).dataTable({
        'iDisplayLength': 50,
        'bLengthChange': false,
        "sScrollX": "100%",
        "bAutoWidth": true
    });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>');
    
    // Create a group
    var createLnk = $('<a>Create</a>');
    createLnk.click(function() {
        groupDialog();
    });
    
    // Edit a group
    var editLnk = $('<a>Edit</a>');
    editLnk.click(function() {
        var groups = $('#' + tableId + ' input[type=checkbox]:checked');
        for (var i in groups) {
            var group = groups.eq(i).attr('name');            
            if (group) {
                // Column order is: name, selectable, network, and description
                var cols = groups.eq(i).parents('tr').find('td');
                var selectable = cols.eq(2).text();                
                var ip = cols.eq(3).text();
                var hostnames = cols.eq(4).text();
                var network = cols.eq(5).text();
                var description = cols.eq(6).text();
                
                editGroupDialog(group, selectable, ip, hostnames, network, description);
            }
        }
    });
        
    // Delete a profile
    var deleteLnk = $('<a>Delete</a>');
    deleteLnk.click(function() {
        var groups = getNodesChecked(tableId);
        if (groups) {
            deleteGroupDialog(groups);
        }
    });
    
    // Refresh profiles table
    var refreshLnk = $('<a>Refresh</a>');
    refreshLnk.click(function() {
        queryGroups(panelId);
    });
    
    // Create an action menu
    var actionsMenu = createMenu([createLnk, editLnk, deleteLnk, refreshLnk]);
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

    // Resize accordion
    $('#' + tableId).parents('.ui-accordion').accordion('resize');
}

/**
 * Open group dialog
 */
function groupDialog() {
    // Create form to add profile
    var dialogId = 'createGroup';
    var groupForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the group.');
    groupForm.append(info);
        
    var group = $('<div><label>Group:</label><input type="text" name="group"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable"/></div>');
    var ip = $('<div><label>IP:</label><input type="text" name="ip"/></div>');
    var hostnames = $('<div><label>Hostnames:</label><input type="text" name="hostnames"/></div>');
    var network = $('<div><label>Network:</label><input type="text" name="network"/></div>');
    var comments = $('<div><label>Description:</label><input type="text" name="comments"/></div>');
    groupForm.append(group, selectable, ip, hostnames, network, comments);
    
    // Open dialog to add image
    groupForm.dialog({
        title:'Create group',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 400,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get group attributes
                var group = $(this).find('input[name="group"]');
                var selectable = $(this).find('input[name="selectable"]');
                var ip = $(this).find('input[name="ip"]');
                var hostnames = $(this).find('input[name="hostnames"]');
                var network = $(this).find('input[name="network"]');
                var comments = $(this).find('input[name="comments"]');
                                
                // Check that group attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(group, ip, hostnames, network);
                for (var i in inputs) {
                    if (!inputs[i].val()) {
                        inputs[i].css('border-color', 'red');
                        ready = 0;
                    } else
                        inputs[i].css('border-color', '');
                }
                
                // If inputs are not complete, show warning message
                if (!ready) {
                    var warn = createWarnBar('Please provide a value for each missing field.');
                    warn.prependTo($(this));
                } else {
                    // Change dialog buttons
                    $(this).dialog('option', 'buttons', {
                        'Close': function() {$(this).dialog("close");}
                    });
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = "updategroup;" + group.val() + ";'" + ip.val() + "';'" + hostnames.val() + "';";
                        
                    if (selectable.attr("checked"))
                        args += "'description:" + comments.val() + "|network:" + network.val() + "|selectable:yes";
                    else
                        args += "'description:" + comments.val() + "|network:" + network.val() + "|selectable:no";
                                                            
                    // Add image to xCAT
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : args,
                            msg : dialogId
                        },
    
                        success : updatePanel
                    });
                }
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Edit group dialog
 * 
 * @param iGroup Group name
 * @param iSelectable Is group selectable from the service page
 * @param iIp Group IP regex
 * @param iHostnames Group hostnames regex
 * @param iNetwork Group network, e.g. 10.1.2.0/24
 * @param iComments Group description
 */
function editGroupDialog(iGroup, iSelectable, iIp, iHostnames, iNetwork, iComments) {
    // Create form to add profile
    var dialogId = 'createGroup';
    var groupForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the group.');
    groupForm.append(info);
        
    var group = $('<div><label>Group:</label><input type="text" name="group"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable"/></div>');
    var ip = $('<div><label>IP:</label><input type="text" name="ip"/></div>');
    var hostnames = $('<div><label>Hostnames:</label><input type="text" name="hostnames"/></div>');
    var network = $('<div><label>Network:</label><input type="text" name="network"/></div>');
    var comments = $('<div><label>Description:</label><input type="text" name="comments"/></div>');
    groupForm.append(group, selectable, ip, hostnames, network, comments);
    
    // Fill in group attributes
    groupForm.find('input[name="group"]').val(iGroup);
    groupForm.find('input[name="ip"]').val(iIp);
    groupForm.find('input[name="hostnames"]').val(iHostnames);
    groupForm.find('input[name="network"]').val(iNetwork);
    groupForm.find('input[name="comments"]').val(iComments);
    if (iSelectable == "yes")
        groupForm.find('input[name="selectable"]').attr('checked', 'checked');
    
    // Open dialog to add image
    groupForm.dialog({
        title:'Edit group',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 400,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get group attributes
                var group = $(this).find('input[name="group"]');
                var selectable = $(this).find('input[name="selectable"]');
                var ip = $(this).find('input[name="ip"]');
                var hostnames = $(this).find('input[name="hostnames"]');
                var network = $(this).find('input[name="network"]');
                var comments = $(this).find('input[name="comments"]');
                                
                // Check that group attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(group, ip, hostnames, network);
                for (var i in inputs) {
                    if (!inputs[i].val()) {
                        inputs[i].css('border-color', 'red');
                        ready = 0;
                    } else
                        inputs[i].css('border-color', '');
                }
                
                // If inputs are not complete, show warning message
                if (!ready) {
                    var warn = createWarnBar('Please provide a value for each missing field.');
                    warn.prependTo($(this));
                } else {
                    // Change dialog buttons
                    $(this).dialog('option', 'buttons', {
                        'Close': function() {$(this).dialog("close");}
                    });
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = "updategroup;" + group.val() + ";'" + ip.val() + "';'" + hostnames.val() + "';";
                        
                    if (selectable.attr("checked"))
                        args += "'description:" + comments.val() + "|network:" + network.val() + "|selectable:yes";
                    else
                        args += "'description:" + comments.val() + "|network:" + network.val() + "|selectable:no";
                                                            
                    // Add image to xCAT
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : args,
                            msg : dialogId
                        },
    
                        success : updatePanel
                    });
                }
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Open dialog to confirm group delete
 * 
 * @param groups Groups to delete
 */
function deleteGroupDialog(groups) {
    // Create form to delete disk to pool
    var dialogId = 'deleteImage';
    var deleteForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Are you sure you want to delete ' + groups.replace(new RegExp(',', 'g'), ', ') + '?');
    deleteForm.append(info);
            
    // Open dialog to delete user
    deleteForm.dialog({
        title:'Delete group',
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
                        args : 'rmgroup;' + groups,
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
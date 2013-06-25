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
                if (!$.cookie('zvms')){
                    $.ajax( {
                        url : 'lib/cmd.php',
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
        "bScrollCollapse": true,
        "sScrollY": "400px",
        "sScrollX": "110%",
        "bAutoWidth": true,
        "oLanguage": {
            "oPaginate": {
              "sNext": "",
              "sPrevious": ""
            }
        }
    });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>').css("width", "400px");
    
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
        
    var imageName = $('<div><label>Image name:</label><input type="text" name="imagename" disabled="disabled" title="The name of the image"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable" title="Select if you want this image to appear on the self service portal"/></div>');
    var imageType = $('<div><label>Image type:</label><input type="text" name="imagetype" value="linux" title="The type of operating system image this definition represents"/></div>');
    var architecture = $('<div><label>OS architecture:</label><input type="text" name="osarch" title="The hardware architecture of this node. Valid values: x86_64, ppc64, x86, ia64, and s390x."/></div>');
    var osName = $('<div><label>OS name:</label><input type="text" name="osname" value="Linux" title="Operating system name"/></div>');
    var osVersion = $('<div><label>OS version:</label><input type="text" name="osvers" title="The Linux operating system deployed on this node. Valid values: rhel*, centos*, fedora*, and sles* (where * is the version #)."/></div>');    
    var profile = $('<div><label>Profile:</label><input type="text" name="profile" title="The node usage category"/></div>');
    var provisionMethod = $('<div><label>Provision method:</label></div>');
    var provisionSelect = $('<select name="provmethod" title="The provisioning method for node deployment">'
            + '<option value=""></option>'
            + '<option value="install">install</option>'
            + '<option value="netboot">netboot</option>'
            + '<option value="statelite">statelite</option>'
        + '</select>');
    provisionMethod.append(provisionSelect);
    var comments = $('<div><label>Description:</label><input type="text" name="comments" title="Any user-written notes"/></div>');
    imageForm.append(imageName, selectable, imageType, architecture, osName, osVersion, profile, provisionMethod, comments);
    
	// Generate tooltips
    imageForm.find('div input[title],textarea[title],select[title]').tooltip({
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
	var inst = 0;
    var dialogId = 'editImage' + inst;
    while ($('#' + dialogId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        dialogId = 'editImage' + inst;
    }
	
	// Create form to add profile
    var imageForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the image. The image name will be generated based on the attributes you will give.');
    imageForm.append(info);
        
    var imageName = $('<div><label>Image name:</label><input type="text" name="imagename" disabled="disabled" title="The name of the image"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable" title="Select if you want this image to appear on the self service portal"/></div>');
    var imageType = $('<div><label>Image type:</label><input type="text" name="imagetype" value="linux" title="The type of operating system image this definition represents"/></div>');
    var architecture = $('<div><label>OS architecture:</label><input type="text" name="osarch" title="The hardware architecture of this node. Valid values: x86_64, ppc64, x86, ia64, and s390x."/></div>');
    var osName = $('<div><label>OS name:</label><input type="text" name="osname" value="Linux" title="Operating system name"/></div>');
    var osVersion = $('<div><label>OS version:</label><input type="text" name="osvers" title="The Linux operating system deployed on this node. Valid values: rhel*, centos*, fedora*, and sles* (where * is the version #)."/></div>');    
    var profile = $('<div><label>Profile:</label><input type="text" name="profile" title="The node usage category"/></div>');
    var provisionMethod = $('<div><label>Provision method:</label></div>');
    var provisionSelect = $('<select name="provmethod" title="The provisioning method for node deployment">'
            + '<option value=""></option>'
            + '<option value="install">install</option>'
            + '<option value="netboot">netboot</option>'
            + '<option value="statelite">statelite</option>'
        + '</select>');
    provisionMethod.append(provisionSelect);
    var comments = $('<div><label>Description:</label><input type="text" name="comments" title="Any user-written notes"/></div>');
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
        
	// Generate tooltips
    imageForm.find('div input[title],textarea[title],select[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "toggle",
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
    table.init(['<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'Name', 'Selectable', 'IP', 'Hostname', 'Description']);

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
                
                // Is the group selectable?
                if (tmp[j].indexOf('selectable:') > -1) {
                    selectable = tmp[j].replace('selectable:', '');
                    selectable = jQuery.trim(selectable);
                }
            }
        }
        
        // Columns are: name, selectable, network, and description
        var cols = new Array(name, selectable, ip, hostname, desc);

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
        "bScrollCollapse": true,
        "sScrollY": "400px",
        "sScrollX": "110%",
        "bAutoWidth": true,
        "oLanguage": {
            "oPaginate": {
              "sNext": "",
              "sPrevious": ""
            }
        }
    });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>').css("width", "400px");
    
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
                var description = cols.eq(5).text();
                
                editGroupDialog(group, selectable, ip, hostnames, description);
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
        
    var group = $('<div><label>Group:</label><input type="text" name="group" title="The group name"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable" title="Select if you want this group to appear on the self service portal"/></div>');
    var ip = $('<div><label>IP:</label><input type="text" name="ip" title="The IP address of the nodes, usually given as a regular expression, e.g. |ihost(\d+)|10.1.1.($1+0)|"/></div>');
    var hostnames = $('<div><label>Hostnames:</label><input type="text" name="hostnames" title="The hostname of the nodes, usually given as a regular expression, e.g. |(.*)|($1).sourceforge.net|"/></div>');
    var comments = $('<div><label>Description:</label><input type="text" name="comments" title="A description of the group"/></div>');
    var ipPool = $('<div><label style="vertical-align: top;">IP pool:</label><textarea name="ip_pool" title="A pool of node names, IP addresses, and hostnames that can be chosen from for a newly provisioned virtual machine. An entry in the pool could be: ihost12,10.1.2.12,ihost12.endicott.ibm.com. A newline separates each entry."/></div>');
    
    groupForm.append(group, selectable, ip, hostnames, comments, ipPool);
    
	// Generate tooltips
    groupForm.find('div input[title],textarea[title],select[title]').tooltip({
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
    
    // Open dialog to add image
    groupForm.dialog({
        title:'Create group',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 600,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get group attributes
                var group = $(this).find('input[name="group"]');
                var selectable = $(this).find('input[name="selectable"]');
                var ip = $(this).find('input[name="ip"]');
                var hostnames = $(this).find('input[name="hostnames"]');
                var comments = $(this).find('input[name="comments"]');
                var ipPool = $(this).find('textarea[name=ip_pool]').val();
                                
                // Check that group attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(group);
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
                    
                    // A newline at the end of IP pool is needed
                    ipPool = ipPool.replace(/^\s+|\s+$/g, '');
                    ipPool += '\n';
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = "updategroup;" + group.val() + ";'" + ip.val() + "';'" + hostnames.val() + "';";
                        
                    if (selectable.attr("checked"))
                        args += "'description:" + comments.val() + "|selectable:yes";
                    else
                        args += "'description:" + comments.val() + "|selectable:no";
                                                            
                    // Add image to xCAT
                    $.ajax({
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
                    
                    // Write IP pool file to /var/tmp
                    $.ajax({
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'write',
                            tgt : '/var/tmp/' + group.val() + '.pool',
                            args : '',
                            cont : ipPool,
                            msg : dialogId + ';' + group.val()
                        },

                        success : function(data) {
                            var args = data.msg.split(';');
                                                        
                            // Create profile in xCAT
                            $.ajax({
                                url : 'lib/cmd.php',
                                dataType : 'json',
                                data : {
                                    cmd : 'webrun',
                                    tgt : '',
                                    args : 'mkippool;' + args[1],
                                    msg : args[0]
                                },
                                
                                success: updatePanel
                            });
                        }
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
 * @param iComments Group description
 */
function editGroupDialog(iGroup, iSelectable, iIp, iHostnames, iComments) {
    // Create form to add profile
    var dialogId = 'createGroup-' + iGroup;
    var groupForm = $('<div id="' + dialogId + '" class="form"></div>');
    
    // Create info bar
    var info = createInfoBar('Provide the following attributes for the group.');
    groupForm.append(info);
        
    var group = $('<div><label>Group:</label><input type="text" name="group" title="The group name"/></div>');
    var selectable = $('<div><label>Selectable:</label><input type="checkbox" name="selectable" title="Select if you want this group to appear on the self service portal"/></div>');
    var ip = $('<div><label>IP:</label><input type="text" name="ip" title="The IP address for the group, usually given as a regular expression, e.g. |ihost(\d+)|10.1.1.($1+0)|"/></div>');
    var hostnames = $('<div><label>Hostnames:</label><input type="text" name="hostnames" title="The hostname for the group, usually given as a regular expression, e.g. |(.*)|($1).sourceforge.net|"/></div>');
    var comments = $('<div><label>Description:</label><input type="text" name="comments" title="A description of the group"/></div>');
    var ipPool = $('<div><label style="vertical-align: top;">IP pool:</label><textarea name="ip_pool" title="A pool of node names, IP addresses, and hostnames that can be chosen from for a newly provisioned virtual machine."/></div>');
    
    groupForm.append(group, selectable, ip, hostnames, comments, ipPool);
    
	// Query IP pool based on group name
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'lsippool;' + iGroup,
            msg : dialogId
        },

        success : function(data) {
        	// Populate textarea with IP pool entries
        	$('#' + data.msg).find('textarea[name="ip_pool"]').val(data.rsp[0]);
        }
    });
    
    // Fill in group attributes
    groupForm.find('input[name="group"]').val(iGroup);
    groupForm.find('input[name="ip"]').val(iIp);
    groupForm.find('input[name="hostnames"]').val(iHostnames);
    groupForm.find('input[name="comments"]').val(iComments);
    if (iSelectable == "yes")
        groupForm.find('input[name="selectable"]').attr('checked', 'checked');
    
	// Generate tooltips
    groupForm.find('div input[title],textarea[title],select[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "toggle",
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
    
    // Open dialog to add image
    groupForm.dialog({
        title:'Edit group',
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 600,
        buttons: {
            "Ok": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get group attributes
                var group = $(this).find('input[name="group"]');
                var selectable = $(this).find('input[name="selectable"]');
                var ip = $(this).find('input[name="ip"]');
                var hostnames = $(this).find('input[name="hostnames"]');
                var comments = $(this).find('input[name="comments"]');
                var ipPool = $(this).find('textarea[name=ip_pool]').val();
                                
                // Check that group attributes are provided before continuing
                var ready = 1;
                var inputs = new Array(group);
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
                    
                    // A newline at the end of IP pool is needed
                    ipPool = ipPool.replace(/^\s+|\s+$/g, '');
                    ipPool += '\n';
                    
                    // Set default description
                    if (!comments.val())
                        comments.val('No description');
                    
                    // Create arguments to send via AJAX
                    var args = "updategroup;" + group.val() + ";'" + ip.val() + "';'" + hostnames.val() + "';";
                        
                    if (selectable.attr("checked"))
                        args += "'description:" + comments.val() + "|selectable:yes";
                    else
                        args += "'description:" + comments.val() + "|selectable:no";
                                                            
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
                    
                    // Write IP pool file to /var/tmp
                    $.ajax({
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'write',
                            tgt : '/var/tmp/' + group.val() + '.pool',
                            args : '',
                            cont : ipPool,
                            msg : dialogId + ';' + group.val()
                        },

                        success : function(data) {
                            var args = data.msg.split(';');
                                                        
                            // Create profile in xCAT
                            $.ajax({
                                url : 'lib/cmd.php',
                                dataType : 'json',
                                data : {
                                    cmd : 'webrun',
                                    tgt : '',
                                    args : 'mkippool;' + args[1],
                                    msg : args[0]
                                },
                                
                                success: updatePanel
                            });
                        }
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
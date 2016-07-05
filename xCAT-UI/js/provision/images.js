/**
 * Global variables
 */
var origAttrs = new Object(); // Original image attributes
var defAttrs; // Definable image attributes
var imgTableId = 'imagesDatatable';    // Images datatable ID
var softwareList = {
    "rsct" : ["rsct.core.utils", "rsct.core", "src"],
    "pe" : ["IBMJava2-142-ppc64-JRE", "ibm_lapi_ip_rh6p", "ibm_lapi_us_rh6p", "IBM_pe_license", "ibm_pe_rh6p", "ppe_pdb_ppc64_rh600", "sci_ppc_32bit_rh600", "sci_ppc_64bit_rh600", "vac.cmp",
            "vac.lib", "vac.lic", "vacpp.cmp", "vacpp.help.pdf", "vacpp.lib", "vacpp.man", "vacpp.rte", "vacpp.rte.lnk", "vacpp.samples", "xlf.cmp", "xlf.help.pdf", "xlf.lib", "xlf.lic", "xlf.man",
            "xlf.msg.rte", "xlf.rte", "xlf.rte.lnk", "xlf.samples", "xlmass.lib", "xlsmp.lib", "xlsmp.msg.rte", "xlsmp.rte"],
    "gpfs" : ["gpfs.base", "gpfs.gpl", "gpfs.gplbin", "gpfs.msg.en_US"],
    "essl" : ["essl.3232.rte", "essl.3264.rte", "essl.6464.rte", "essl.common", "essl.license", "essl.man", "essl.msg", "essl.rte", "ibm-java2", "pessl.common", "pessl.license", "pessl.man",
            "pessl.msg", "pessl.rte.ppe"],
    "loadl" : ["IBMJava2", "LoadL-full-license-RH6", "LoadL-resmgr-full-RH6", "LoadL-scheduler-full-RH6"],
    "ganglia" : ["rrdtool", "ganglia", "ganglia-gmetad", "ganglia-gmond"],
    "base" : ["createrepo"]
};

/**
 * Load images page
 */
function loadImagesPage() {
    // Set padding for images page
    $('#imagesTab').css('padding', '20px 60px');

    // Get images within the database
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage;-l',
            msg : ''
        },

        success : loadImages
    });
}

/**
 * Load images within the database
 *
 * @param data Data returned from HTTP request
 */
function loadImages(data) {
    // Data returned
    var rsp = data.rsp;
    if (rsp[0].indexOf('Could not find any object definitions') > -1) {
    	rsp = new Array();
    }

    // Image attributes hash
    var attrs = new Object();
    // Image attributes
    var headers = new Object();

    // Clear hash table containing image attributes
    origAttrs = '';

    var image;
    var args;
    for (var i in rsp) {
        // Get the image
        var pos = rsp[i].indexOf('Object name:');
        if (pos > -1) {
            var temp = rsp[i].split(': ');
            image = jQuery.trim(temp[1]);

            // Create a hash for the image attributes
            attrs[image] = new Object();
            i++;
        }

        // Get key and value
        args = rsp[i].split('=');
        var key = jQuery.trim(args[0]);
        var val = jQuery.trim(args[1]);

        // Create a hash table
        attrs[image][key] = val;
        headers[key] = 1;
    }

    // Save attributes in hash table
    origAttrs = attrs;

    // Sort headers
    var sorted = new Array();
    for (var key in headers) {
        sorted.push(key);
    }
    sorted.sort();

    // Add column for check box and image name
    sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'imagename');

    // Create a datatable
    var dTable = new DataTable(imgTableId);
    dTable.init(sorted);

    // Go through each image
    for (var img in attrs) {
        // Create a row
        var row = new Array();
        // Create a check box
        var checkBx = '<input type="checkbox" name="' + img + '"/>';
        // Push in checkbox and image name
        row.push(checkBx, img);

        // Go through each header
        for (var i = 2; i < sorted.length; i++) {
            // Add the node attributes to the row
            var key = sorted[i];
            var val = attrs[img][key];
            if (val) {
                row.push(val);
            } else {
                row.push('');
            }
        }

        // Add the row to the table
        dTable.add(row);
    }

    // Clear the tab before inserting the table
    $('#imagesTab').children().remove();

    // Create info bar for images tab
    var info = createInfoBar('Double click on a cell to edit.  Click outside the table to save changes.  Hit the Escape key to ignore changes.');
    $('#imagesTab').append(info);

    /**
     * The following actions are available for images:
     * copy Linux distribution and edit image properties
     */

    // Copy CD into install directory
    var copyCDLnk = $('<a>Copy CD</a>');
    copyCDLnk.click(function() {
        openCopyCdDialog();
    });

    // Generate stateless or statelite image
    var generateLnk = $('<a>Generate image</a>');
    generateLnk.click(function() {
        loadCreateImage();
    });

    // Edit image attributes
    var editLnk = $('<a>Edit</a>');
    editLnk.click(function() {
        var tgtImages = getNodesChecked(imgTableId).split(',');
        if (tgtImages) {
            for (var i in tgtImages) {
                 openEditImagePage(tgtImages[i]);
            }
        }
    });

    // Add a row
    var addLnk = $('<a>Add</a>');
    addLnk.click(function() {
        openAddImageDialog();
    });

    // Remove a row
    var removeLnk = $('<a>Remove</a>');
    removeLnk.click(function() {
        var images = getNodesChecked(imgTableId);
        if (images) {
            confirmImageDeleteDialog(images);
        }
    });

    // Refresh image table
    var refreshLnk = $('<a>Refresh</a>');
    refreshLnk.click(function() {
        // Get images within the database
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'lsdef',
                tgt : '',
                args : '-t;osimage;-l',
                msg : ''
            },

            success : loadImages
        });
    });

    // Insert table
    $('#imagesTab').append(dTable.object());

    // Turn table into a datatable
    var myDataTable = $('#' + imgTableId).dataTable({
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

    // Set datatable width
    $('#' + imgTableId + '_wrapper').css({
        'width': '880px'
    });

    // Actions
    var actionBar = $('<div class="actionBar"></div>').css("width", "450px");
    var advancedLnk = '<a>Advanced</a>';
    var advancedMenu = createMenu([copyCDLnk, generateLnk]);

    // Create an action menu
    var actionsMenu = createMenu([refreshLnk, addLnk, editLnk, removeLnk, [advancedLnk, advancedMenu]]);
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
    var menuDiv = $('<div id="' + imgTableId + '_menuDiv" class="menuDiv"></div>');
    $('#' + imgTableId + '_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);
    $('#' + imgTableId + '_filter').appendTo(menuDiv);

    /**
     * Enable editable columns
     */

    // Do not make 1st or 2nd columns editable
    $('#' + imgTableId + ' td:not(td:nth-child(1),td:nth-child(2))').editable(
        function(value, settings) {
            // Get column index
            var colPos = this.cellIndex;

            // Get row index
            var dTable = $('#' + imgTableId).dataTable();
            var rowPos = dTable.fnGetPosition(this.parentNode);

            // Update datatable
            dTable.fnUpdate(value, rowPos, colPos);

            // Get image name
            var image = $(this).parent().find('td:eq(1)').text();

            // Get table headers
            var headers = $('#' + imgTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');

            // Get attribute name
            var attrName = jQuery.trim(headers.eq(colPos).text());
            // Get column value
            var value = $(this).text();
            // Build argument
            var args = attrName + '=' + value;

            // Send command to change image attributes
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'chdef',
                    tgt : '',
                    args : '-t;osimage;-o;' + image + ';' + args,
                    msg : 'out=imagesTab;tgt=' + image
                },

                success: showChdefOutput
            });

            return value;
        }, {
            onblur : 'submit',     // Clicking outside editable area submits changes
            type : 'textarea',    // Input type to use
            placeholder: ' ',
            event : "dblclick", // Double click and edit
            height : '30px'     // The height of the text area
        });

    // Get definable node attributes
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage;-h',
            msg : ''
        },

        success : setImageDefAttrs
    });
}

/**
 * Open dialog to confirm deleting image
 *
 * @param images Comma delimited image names
 */
function confirmImageDeleteDialog(images) {
    // Make images list more readable
    var dialogId = 'confirmImageRemove';
    var tmp = images.replace(new RegExp(',', 'g'), ', ');
    var confirmDialog = $('<div id="' + dialogId + '">'
            + '<p>Are you sure you want to remove ' + tmp + '?</p>'
        + '</div>');

    // Open dialog to confirm delete
    confirmDialog.dialog({
        modal: true,
        close: function(){
            $(this).remove();
        },
        title: 'Confirm',
        width: 500,
        buttons: {
            "Ok": function(){
                // Change dialog buttons
                $(this).dialog('option', 'buttons', {
                    'Close': function() {$(this).dialog("close");}
                });

                // Add image to xCAT
                $.ajax( {
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'rmdef',
                        tgt : '',
                        args : '-t;osimage;-o;' + images,
                        msg : dialogId
                    },

                    success : updateImageDialog
                });
            },
            "Cancel": function(){
                $(this).dialog("close");
            }
        }
    });
}

/**
 * Open a dialog to add an image
 */
function openAddImageDialog() {
    // Create dialog to add image
    var dialogId = 'addImage';
    var addImageForm = $('<div id="' + dialogId + '" class="form"></div>');

    // Create info bar
    var info = createInfoBar('Provide the following attributes for the image. The image name will be generated based on the attributes you will give.');

    var imageFS = $('<fieldset></fieldset>');
    var imageLegend = $('<legend>Image</legend>');
    imageFS.append(imageLegend);
    var imageAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imageFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
    imageFS.append(imageAttr);

    var optionFS = $('<fieldset></fieldset>');
    var optionLegend = $('<legend>Options</legend>');
    optionFS.append(optionLegend);
    var optionAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    optionFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>'));
    optionFS.append(optionAttr);

    addImageForm.append(info, imageFS, optionFS);

    // Create inputs for image attributes
    var imageName = $('<div><label>Image name:</label><input type="text" name="imagename" disabled="disabled" title="The name of this xCAT OS image definition"/></div>');
    var imageType = $('<div><label>Image type:</label><input type="text" name="imagetype" value="linux" title="The type of operating system image this definition represents"/></div>');
    var architecture = $('<div><label>OS architecture:</label><input type="text" name="osarch" title="The hardware architecture of this image. Valid values: s390x."/></div>');
    var osName = $('<div><label>OS name:</label><input type="text" name="osname" value="Linux" title="Operating system name"/></div>');
    var osVersion = $('<div><label>OS version:</label><input type="text" name="osvers" title="The operating system deployed on this node. Valid values: rhel*, sles* (where * is the version #)."/></div>');
    var profile = $('<div><label>Profile:</label><input type="text" name="profile" title="The node usage category"/></div>');
    var provisionMethod = $('<div><label>Provision method:</label></div>');
    var provisionSelect = $('<select name="provmethod" title="The provisioning method for node deployment">'
            + '<option value=""></option>'
            + '<option value="install">install</option>'
            + '<option value="netboot">netboot</option>'
            + '<option value="statelite">statelite</option>'
        + '</select>');
    provisionMethod.append(provisionSelect);

    // Create inputs for optional attributes
    var otherpkgDirectory = $('<div><label>Other package directory:</label></div>');
    var otherpkgDirectoryInput = $('<input type="text" name="otherpkgdir" title="The base directory where the non-distro packages are stored"/>');
    otherpkgDirectory.append(otherpkgDirectoryInput);
    otherpkgDirectoryInput.serverBrowser({
        onSelect : function(path) {
            $('#addImage input[name="otherpkgdir"]').val(path);
        },
        onLoad : function() {
            return $('#addImage input[name="otherpkgdir"]').val();
        },
        knownPaths : [{
            text : 'Install',
            image : 'desktop.png',
            path : '/install'
        }],
        imageUrl : 'images/serverbrowser/',
        systemImageUrl : 'images/serverbrowser/',
        handlerUrl : 'lib/getpath.php',
        title : 'Browse',
        requestMethod : 'POST',
        width : '500',
        height : '300',
        basePath : '/install' // Limit user to only install directory
    });
    var packageDirectory = $('<div><label>Package directory:</label></div>');
    var packageDirectoryInput = $('<input type="text" name="pkgdir" title="The name of the directory where the distro packages are stored"/>');
    packageDirectory.append(packageDirectoryInput);
    packageDirectoryInput.serverBrowser({
        onSelect : function(path) {
            $('#addImage input[name="pkgdir"]').val(path);
        },
        onLoad : function() {
            return $('#addImage input[name="pkgdir"]').val();
        },
        knownPaths : [{
            text : 'Install',
            image : 'desktop.png',
            path : '/install'
        }],
        imageUrl : 'images/serverbrowser/',
        systemImageUrl : 'images/serverbrowser/',
        handlerUrl : 'lib/getpath.php',
        title : 'Browse',
        requestMethod : 'POST',
        width : '500',
        height : '300',
        basePath : '/install' // Limit user to only install directory
    });
    var packageList = $('<div><label>Package list:</label></div>');
    var packageListInput = $('<input type="text" name="pkglist" title="The fully qualified name of the file that stores the distro packages list that will be included in the image"/>');
    packageList.append(packageListInput);
    packageListInput.serverBrowser({
        onSelect : function(path) {
            $('#addImage input[name="pkglist"]').val(path);
        },
        onLoad : function() {
            return $('#addImage input[name="pkglist"]').val();
        },
        knownPaths : [{
            text : 'Install',
            image : 'desktop.png',
            path : '/install'
        }],
        imageUrl : 'images/serverbrowser/',
        systemImageUrl : 'images/serverbrowser/',
        handlerUrl : 'lib/getpath.php',
        title : 'Browse',
        requestMethod : 'POST',
        width : '500',
        height : '300',
        basePath : '/install' // Limit user to only install directory
    });
    var template = $('<div><label>Template:</label></div>');
    var templateInput = $('<input type="text" name="template" title="The fully qualified name of the template file that is used to create the kickstart or autoyast file for diskful installation"/>');
    template.append(templateInput);
    templateInput.serverBrowser({
        onSelect : function(path) {
            $('#addImage input[name="template"]').val(path);
        },
        onLoad : function() {
            return $('#addImage input[name="template"]').val();
        },
        knownPaths : [{
            text : 'Install',
            image : 'desktop.png',
            path : '/install'
        }],
        imageUrl : 'images/serverbrowser/',
        systemImageUrl : 'images/serverbrowser/',
        handlerUrl : 'lib/getpath.php',
        title : 'Browse',
        requestMethod : 'POST',
        width : '500',
        height : '300',
        basePath : '/install' // Limit user to only install directory
    });

    imageAttr.append(imageName, imageType, architecture, osName, osVersion, profile, provisionMethod);
    optionAttr.append(otherpkgDirectory, packageDirectory, packageList, template);

	// Generate tooltips
    addImageForm.find('div input[title],select[title]').tooltip({
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
    addImageForm.dialog({
        title:'Add image',
        modal: true,
        close: function(){
            $(this).remove();
        },
        beight: 400,
        width: 600,
        buttons: {
            "Ok": function(){
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();

                // Get image attributes
                var imageType = $(this).find('input[name="imagetype"]');
                var architecture = $(this).find('input[name="osarch"]');
                var osName = $(this).find('input[name="osname"]');
                var osVersion = $(this).find('input[name="osvers"]');
                var profile = $(this).find('input[name="profile"]');
                var provisionMethod = $(this).find('select[name="provmethod"]');

                // Get optional image attributes
                var otherpkgDirectory = $(this).find('input[name="otherpkgdir"]');
                var pkgDirectory = $(this).find('input[name="pkgdir"]');
                var pkgList = $(this).find('input[name="pkglist"]');
                var template = $(this).find('input[name="template"]');

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

                    // Create arguments to send via AJAX
                    var args = '-t;osimage;-o;' + imageName.val() + ';' +
                        'imagetype=' + imageType.val() + ';' +
                        'osarch=' + architecture.val() + ';' +
                        'osname=' + osName.val() + ';' +
                        'osvers=' + osVersion.val() + ';' +
                        'profile=' + profile.val() + ';' +
                        'provmethod=' + provisionMethod.val();

                    // Get optional attributes
                    if (otherpkgDirectory.val())
                        args += ';otherpkgdir=' + otherpkgDirectory.val();
                    if (pkgDirectory.val())
                        args += ';pkgdir=' + pkgDirectory.val();
                    if (pkgList.val())
                        args += ';pkglist=' + pkgList.val();
                    if (template.val())
                        args += ';template=' + template.val();

                    // Add image to xCAT
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'chdef',
                            tgt : '',
                            args : args,
                            msg : dialogId
                        },

                        success : updateImageDialog
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
 * Update image dialog
 *
 * @param data HTTP request data
 */
function updateImageDialog(data) {
    var dialogId = data.msg;
    var infoMsg;

    // Delete loader if one does exist
    $('.ui-dialog #' + dialogId + ' img[src="images/loader.gif"]').remove();

    // Create info message
    if (jQuery.isArray(data.rsp)) {
        infoMsg = '';

        // If the data returned is more than 10 lines, get only the last line
        var i, start;
        if (data.rsp.length > 10)
            start = data.rsp.length - 1;
        else
            start = 0;

        for (i = start; i < data.rsp.length; i++)
            infoMsg += data.rsp[i] + '</br>';
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

    var msg = $('<p>' + infoMsg + '</p>').css({
        'display': 'inline-block',
        'width': '90%'
    });

    infoBar.append(icon, msg, close);
    infoBar.prependTo($('.ui-dialog #' + dialogId));
}

/**
 * Set definable image attributes
 *
 * @param data Data returned from HTTP request
 */
function setImageDefAttrs(data) {
    // Clear hash table containing definable image attributes
    defAttrs = new Array();

    // Get definable attributes
    var attrs = data.rsp[2].split(/\n/);

    // Go through each line
    var attr, key, descr;
    for (var i in attrs) {
        attr = attrs[i];

        // If the line is not empty
        if (attr) {
            // If the line has the attribute name
            if (attr.indexOf(':') && attr.indexOf(' ')) {
                // Get attribute name and description
                key = jQuery.trim(attr.substring(0, attr.indexOf(':')));
                descr = jQuery.trim(attr.substring(attr.indexOf(':') + 1));
                descr = descr.replace(new RegExp('<', 'g'), '[').replace(new RegExp('>', 'g'), ']');

                // Set hash table where key = attribute name and value = description
                defAttrs[key] = descr;
            } else {
                // Append description to hash table
                defAttrs[key] = defAttrs[key] + '\n' + attr.replace(new RegExp('<', 'g'), '[').replace(new RegExp('>', 'g'), ']');
            }
        } // End of if
    } // End of for
}

/**
 * Load create image page
 */
function loadCreateImage() {
    // Get nodes tab
    var tab = getProvisionTab();
    var tabId = 'createImageTab';

    // Generate new tab ID
    if ($('#' + tabId).size()) {
        tab.select(tabId);
        return;
    }

    var imageOsVers = $.cookie("osvers").split(",");
    var imageArch = $.cookie("osarchs").split(",");
    var profiles = $.cookie("profiles").split(",");

    var createImgForm = $('<div class="form"></div>');
    var createImgFS = $('<fieldset></fieldset>').append('<legend>Create Image</legend>');
    createImgForm.append(createImgFS);

    // Show info bar
    var infoBar = createInfoBar('Specify the parameters for the image (stateless or statelite) you want to create, then click Create.');
    createImgFS.append(infoBar);

    // Drop down for OS versions
    var osVerSelect = $('<select id="osvers" onchange="hpcShow()"></select>');
    for (var i in imageOsVers)
        osVerSelect.append('<option value="' + imageOsVers[i] + '">' + imageOsVers[i] + '</option>');
    createImgFS.append($('<div><label>OS version:</label></div>').append(osVerSelect));

    // Drop down for OS architectures
    var imgSelect = $('<select id="osarch" onchange="hpcShow()"></select>');
    for (var i in imageArch)
        imgSelect.append('<option value="' + imageArch[i] + '">' + imageArch[i] + '</option>');
    createImgFS.append($('<div><label>OS architecture:</label></div>').append(imgSelect));

    // Netboot interface input
    createImgFS.append($('<div><label>Netboot interface:</label><input type="text" id="netbootif"/></div>'));

    // Profile selector
    var profileSelect = $('<select id="profile" onchange="hpcShow()">');
    for (var i in profiles)
        profileSelect.append('<option value="' + profiles[i] + '">' + profiles[i] + '</option>');
    createImgFS.append($('<div><label>Profile:</label></div>').append(profileSelect));

    // Boot method drop down
    createImgFS.append($('<div><label>Boot method:</label>' +
        '<select id="bootmethod">' +
            '<option value="stateless">stateless</option>' +
            '<option value="statelite">statelite</option>' +
        '</select></div>'));

    // Create HPC software stack fieldset
    createHpcFS(createImgForm);

    // The button used to create images is created here
    var createImageBtn = createButton("Create");
    createImageBtn.bind('click', function(event) {
        createImage();
    });

    createImgForm.append(createImageBtn);

    // Add tab
    tab.add(tabId, 'Create', createImgForm, true);
    tab.select(tabId);

    // Check the selected OS version and OS arch for HPC stack
    // If they are valid, show the HCP stack fieldset
    hpcShow();
}

/**
 * Create HPC fieldset
 *
 * @param container The container to hold the HPC fieldset
 */
function createHpcFS(container) {
    var hpcFieldset = $('<fieldset id="hpcsoft"></fieldset>');
    hpcFieldset.append('<legend>HPC Software Stack</legend>');

    var str = 'Before selecting the software, you should have the following already completed on your xCAT cluster:<br/><br/>'
            + '1. If you are using the xCAT hierarchy, your service nodes are installed and running.<br/>'
            + '2. Your compute nodes are defined in xCAT, and you have verified your hardware control capabilities, '
            + 'gathered MAC addresses, and done all the other necessary preparations for a diskless install.<br/>'
            + '3. You should have a diskless image created with the base OS installed and verified it on at least one test node.<br/>'
            + '4. You should install the software on the management node and copy all correponding packages into the location "/install/custom/otherpkgs/" based on '
            + 'these <a href="http://sourceforge.net/apps/mediawiki/xcat/index.php?title=IBM_HPC_Stack_in_an_xCAT_Cluster" target="_blank">documents</a>.<br/>';
    hpcFieldset.append(createInfoBar(str));

    // Advanced software
    str = '<div id="partlysupport"><ul><li id="gpfsli"><input type="checkbox" onclick="softwareCheck(this)" name="gpfs">GPFS</li>' +
        '<li id="rsctli"><input type="checkbox" onclick="softwareCheck(this)" name="rsct">RSCT</li>' +
        '<li id="peli"><input type="checkbox" onclick="softwareCheck(this)" name="pe">PE</li>' +
        '<li id="esslli"><input type="checkbox" onclick="esslCheck(this)" name="essl">ESSl & PESSL</li>' +
        '</ul></div>' +
        '<div><ul><li id="gangliali"><input type="checkbox" onclick="softwareCheck(this)" name="ganglia">Ganglia</li>' +
        '</ul></div>';
    hpcFieldset.append(str);

    container.append($('<div></div>').append(hpcFieldset));
}

/**
 * Check the dependance for ESSL and start the software check for ESSL
 *
 * @param softwareObject The checkbox object of ESSL
 */
function esslCheck(softwareObject) {
    var softwareName = softwareObject.name;
    if (!$('#createImageTab input[name=pe]').attr('checked')) {
        var warnBar = createWarnBar('You must first select the PE');
        $(':checkbox[name=essl]').attr("checked", false);

        // Clear existing warnings and append new warning
        $('#hpcsoft .ui-state-error').remove();
        $('#hpcsoft').prepend(warnBar);

        return;
    } else {
        softwareCheck(softwareObject);
    }
}

/**
 * Check the parameters for the HPC software
 *
 * @param softwareObject Checkbox object of the HPC software
 * @return True if the checkbox is checked, false otherwise
 */
function softwareCheck(softwareObject) {
    var softwareName = softwareObject.name;
    $('#createImageTab #' + softwareName + 'li .ui-state-error').remove();
    $('#createImageTab #' + softwareName + 'li').append(createLoader());
    var cmdString = genRpmCmd(softwareName);
    $.ajax( {
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : cmdString,
            msg : softwareName
        },
        success : function(data) {
            if (rpmCheck(data.rsp, data.msg)) {
                genLsCmd(data.msg);
                $.ajax( {
                    url : 'lib/systemcmd.php',
                    dataType : 'json',
                    data : {
                        cmd : genLsCmd(data.msg),
                        msg : data.msg
                    },
                    success : rpmCopyCheck
                });
            }
        }
    });
}

/**
 * Check if the RPMs are copied to the special location
 *
 * @param data Data returned from HTTP request
 */
function rpmCopyCheck(data) {
    // Remove the loading image
    var errorStr = '';
    var softwareName = data.msg;

    // Check the return information
    var reg = /.+:(.+): No such.*/;
    var resultArray = data.rsp.split("\n");
    for ( var i in resultArray) {
        var temp = reg.exec(resultArray[i]);
        if (temp) {
            // Find out the path and RPM name
            var pos = temp[1].lastIndexOf('/');
            var path = temp[1].substring(0, pos);
            var rpmName = temp[1].substring(pos + 1).replace('*', '');
            errorStr += 'copy ' + rpmName + ' to ' + path + '<br/>';
        }
    }
    $('#createImageTab #' + softwareName + 'li').find('img').remove();

    // No error, show the check image
    if (!errorStr) {
        var infoPart = '<div style="display:inline-block; margin:0px"><span class="ui-icon ui-icon-circle-check"></span></div>';
        $('#createImageTab #' + softwareName + 'li').append(infoPart);
    } else {
        // Show the error message
        errorStr = 'To install the RSCT on your compute node. You should:<br/>' + errorStr + '</div>';
        var warnBar = createWarnBar(errorStr);
        $(':checkbox[name=' + softwareName + ']').attr("checked", false);

        // Clear existing warnings and append new warning
        $('#hpcsoft .ui-state-error').remove();
        $('#hpcsoft').prepend(warnBar);
    }
}

/**
 * Generate the RPM command for rpmcheck
 *
 * @param softwareName The name of the software
 * @return The RPM command
 */
function genRpmCmd(softwareName) {
    var cmdString;
    cmdString = 'rpm -q ';
    for (var i in softwareList[softwareName]) {
        cmdString += softwareList[softwareName][i] + ' ';
    }

    for (var i in softwareList['base']) {
        cmdString += softwareList['base'][i] + ' ';
    }

    return cmdString;
}

/**
 * Check if the RPMs for the HPC software are copied to the special location
 *
 * @param softwareName The name of the software
 */
function genLsCmd(softwareName) {
    var osvers = $('#createImageTab #osvers').val();
    var osarch = $('#createImageTab #osarch').val();
    var path = '/install/post/otherpkgs/' + osvers + '/' + osarch + '/' + softwareName;
    var checkCmd = 'ls ';

    for (var i in softwareList[softwareName]) {
        checkCmd += path + '/' + softwareList[softwareName][i] + '*.rpm ';
    }
    checkCmd += '2>&1';

    return checkCmd;
}

/**
 * Check if all RPMs are installed
 *
 * @param checkInfo 'rpm -q' output
 * @return True if all RPMs are installed, false otherwise
 */
function rpmCheck(checkInfo, name) {
    var errorStr = '';

    var checkArray = checkInfo.split('\n');
    for (var i in checkArray) {
        if (checkArray[i].indexOf('not install') != -1) {
            errorStr += checkArray[i] + '<br/>';
        }
    }

    if (!errorStr) {
        return true;
    }

    errorStr = errorStr.substr(0, errorStr.length - 1);
    $(':checkbox[name=' + name + ']').attr('checked', false);

    // Add the error
    var warnBar = createWarnBar(errorStr);
    $('#createImageTab #' + name + 'li').find('img').remove();

    // Clear existing warnings and append new warning
    $('#hpcsoft .ui-state-error').remove();
    $('#hpcsoft').prepend(warnBar);

    return;
}

/**
 * Check the option and decide whether to show the hpcsoft or not
 */
function hpcShow() {
    // The current UI only supports RHELS 6
    // If you want to support all, delete the subcheck
    if ($('#createImageTab #osvers').attr('value') != "rhels6" || $('#createImageTab #osarch').attr('value') != "ppc64" || $('#createImageTab #profile').attr('value') != "compute") {
        $('#createImageTab #partlysupport').hide();
    } else {
        $('#createImageTab #partlysupport').show();
    }
}

/**
 * Load set image properties page
 *
 * @param tgtImage Target image to set properties
 */
function openEditImagePage(tgtImage) {
    // Get nodes tab
    var tab = getProvisionTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'editImageTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'editImageTab' + inst;
    }

    // Open new tab
    // Create set properties form
    var setPropsForm = $('<div class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Choose the properties you wish to change on the node. When you are finished, click Save.');
    setPropsForm.append(infoBar);

    // Create an input for each definable attribute
    var div, label, input, value;
    var attrIndex = 0;
    // Set node attribute
    origAttrs[tgtImage]['imagename'] = tgtImage;
    for (var key in defAttrs) {
        // If an attribute value exists
        if (origAttrs[tgtImage][key]) {
            // Set the value
            value = origAttrs[tgtImage][key];
        } else {
            value = '';
        }

        // Create label and input for attribute
        div = $('<div></div>').css('display', 'inline');
        label = $('<label>' + key + ':</label>').css('vertical-align', 'middle');
        input = $('<input type="text" id="' + key + '" value="' + value + '" title="' + defAttrs[key] + '"/>').css({
            'margin-top': '5px',
            'float': 'none',
            'width': 'inherit'
        });

        // There is an element called groups that will override the defaults for the groups attribute.
        // Hence, the input must have use CSS to override the float and width.

        // Split attributes into 2 per row
        if (attrIndex > 0 && !(attrIndex % 2)) {
            div.css('display', 'inline-block');
        }

        attrIndex++;

        // Create server browser
        switch (key) {
            case 'pkgdir':
                input.serverBrowser({
                    onSelect : function(path) {
                        $('#pkgdir').val(path);
                    },
                    onLoad : function() {
                        return $('#pkgdir').val();
                    },
                    knownExt : [ 'exe', 'js', 'txt' ],
                    knownPaths : [{
                        text : 'Install',
                        image : 'desktop.png',
                        path : '/install'
                    }],
                    imageUrl : 'images/serverbrowser/',
                    systemImageUrl : 'images/serverbrowser/',
                    handlerUrl : 'lib/getpath.php',
                    title : 'Browse',
                    requestMethod : 'POST',
                    width : '500',
                    height : '300',
                    basePath : '/install' // Limit user to only install directory
                });
                break;
            case 'otherpkgdir':
                input.serverBrowser({
                    onSelect : function(path) {
                        $('#otherpkgdir').val(path);
                    },
                    onLoad : function() {
                        return $('#otherpkgdir').val();
                    },
                    knownExt : [ 'exe', 'js', 'txt' ],
                    knownPaths : [{
                        text : 'Install',
                        image : 'desktop.png',
                        path : '/install'
                    }],
                    imageUrl : 'images/serverbrowser/',
                    systemImageUrl : 'images/serverbrowser/',
                    handlerUrl : 'lib/getpath.php',
                    title : 'Browse',
                    requestMethod : 'POST',
                    width : '500',
                    height : '300',
                    basePath : '/install' // Limit user to only install directory
                });
                break;
            case 'pkglist':
                input.serverBrowser({
                    onSelect : function(path) {
                        $('#pkglist').val(path);
                    },
                    onLoad : function() {
                        return $('#pkglist').val();
                    },
                    knownExt : [ 'exe', 'js', 'txt' ],
                    knownPaths : [{
                        text : 'Install',
                        image : 'desktop.png',
                        path : '/install'
                    }],
                    imageUrl : 'images/serverbrowser/',
                    systemImageUrl : 'images/serverbrowser/',
                    handlerUrl : 'lib/getpath.php',
                    title : 'Browse',
                    requestMethod : 'POST',
                    width : '500',
                    height : '300',
                    basePath : '/opt/xcat/share' // Limit user to only install directory
                });
                break;
            case 'otherpkglist':
                input.serverBrowser({
                    onSelect : function(path) {
                        $('#otherpkglist').val(path);
                    },
                    onLoad : function() {
                        return $('#otherpkglist').val();
                    },
                    knownExt : [ 'exe', 'js', 'txt' ],
                    knownPaths : [{
                        text : 'Install',
                        image : 'desktop.png',
                        path : '/install'
                    }],
                    imageUrl : 'images/serverbrowser/',
                    systemImageUrl : 'images/serverbrowser/',
                    handlerUrl : 'lib/getpath.php',
                    title : 'Browse',
                    requestMethod : 'POST',
                    width : '500',
                    height : '300',
                    basePath : '/install' // Limit user to only install directory
                });
                break;
            case 'template':
                input.serverBrowser({
                    onSelect : function(path) {
                        $('#template').val(path);
                    },
                    onLoad : function() {
                        return $('#template').val();
                    },
                    knownExt : [ 'exe', 'js', 'txt' ],
                    knownPaths : [{
                        text : 'Install',
                        image : 'desktop.png',
                        path : '/install'
                    }],
                    imageUrl : 'images/serverbrowser/',
                    systemImageUrl : 'images/serverbrowser/',
                    handlerUrl : 'lib/getpath.php',
                    title : 'Browse',
                    requestMethod : 'POST',
                    width : '500',
                    height : '300',
                    basePath : '/opt/xcat/share' // Limit user to only install directory
                });
                break;
            default:
                // Do nothing
        }

        // Change border to blue onchange
        input.bind('change', function(event) {
            $(this).css('border-color', 'blue');
        });

        div.append(label, input);
        setPropsForm.append(div);
    }

    // Change style for last division
    div.css({
        'display': 'block',
        'margin': '0px 0px 10px 0px'
    });

    // Generate tooltips
    setPropsForm.find('div input[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.8,
        delay: 500,
        predelay: 800,
        events: {
          def:     "mouseover,mouseout",
          input:   "mouseover,mouseout",
          widget:  "focus mouseover,blur mouseout",
          tooltip: "mouseover,mouseout"
        }
    });

    /**
     * Save
     */
    var saveBtn = createButton('Save');
    saveBtn.bind('click', function(event) {
        // Get all inputs
        var inputs = $('#' + newTabId + ' input');

        // Go through each input
        var args = '';
        var attrName, attrVal;
        inputs.each(function(){
            // If the border color is blue
            if ($(this).css('border-left-color') == 'rgb(0, 0, 255)') {
                // Change border color back to normal
                $(this).css('border-color', '');

                // Get attribute name and value
                attrName = $(this).parent().find('label').text().replace(':', '');
                attrVal = $(this).val();

                // Build argument string
                if (args) {
                    // Handle subsequent arguments
                    args += ';' + attrName + '=' + attrVal;
                } else {
                    // Handle the 1st argument
                    args += attrName + '=' + attrVal;
                }
            }
        });

        // Send command to change image attributes
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'chdef',
                tgt : '',
                args : '-t;osimage;-o;' + tgtImage + ';' + args,
                msg : 'out=' + newTabId + ';tgt=' + tgtImage
            },

            success: showChdefOutput
        });
    });
    setPropsForm.append(saveBtn);

    /**
     * Cancel
     */
    var cancelBtn = createButton('Cancel');
    cancelBtn.bind('click', function(event) {
        // Close the tab
        tab.remove($(this).parent().parent().attr('id'));
    });
    setPropsForm.append(cancelBtn);

    // Append to discover tab
    tab.add(newTabId, 'Edit', setPropsForm, true);

    // Select new tab
    tab.select(newTabId);
}

/**
 * Load copy CD page
 */
function openCopyCdDialog() {
    // Create copy Linux form
    var dialogId = 'imageCopyCd';
    var copyLinuxForm = $('<div id="' + dialogId + '" class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Copy Linux distributions and service levels from CDs or DVDs to the install directory.');
    copyLinuxForm.append(infoBar);

    // Create Linux ISO input
    var iso = $('<div></div>');
    var isoLabel = $('<label> Linux ISO/DVD:</label>').css('vertical-align', 'middle');
    var isoInput = $('<input type="text" id="iso" name="iso" title="The fully qualified name of the disk image file"/>').css('width', '300px');
    iso.append(isoLabel);
    iso.append(isoInput);
    copyLinuxForm.append(iso);

    // Create architecture input
    copyLinuxForm.append('<div><label>Architecture:</label><input type="text" id="arch" name="arch" title="The hardware architecture of this node. Valid values: s390x."/></div>');
    // Create distribution input
    copyLinuxForm.append('<div><label>Distribution:</label><input type="text" id="distro" name="distro" title="The operating system name. Valid values: rhel*, sles* (where * is the version #).<br>Note: dashes are parsed to fill in distro, profile, os, and arch fields in xCAT table."/></div>');

    /**
     * Browse
     */
    var browseBtn = createButton('Browse');
    iso.append(browseBtn);
    // Browse server directory and files
    browseBtn.serverBrowser({
        onSelect : function(path) {
            $('#imageCopyCd #iso').val(path);
        },
        onLoad : function() {
            return $('#imageCopyCd #iso').val();
        },
        knownExt : [ 'exe', 'js', 'txt' ],
        knownPaths : [ {
            text : 'Install',
            image : 'desktop.png',
            path : '/install'
        } ],
        imageUrl : 'images/serverbrowser/',
        systemImageUrl : 'images/serverbrowser/',
        handlerUrl : 'lib/getpath.php',
        title : 'Browse',
        requestMethod : 'POST',
        width : '500',
        height : '300',
        basePath : '/install' // Limit user to only install directory
    });

	// Generate tooltips
    copyLinuxForm.find('div input[title],select[title]').tooltip({
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

    // Open dialog to copy CD
    copyLinuxForm.dialog({
        title:'Copy CD',
        close: function(){
            $(this).remove();
        },
        modal: true,
        width: 600,
        buttons: {
            "Copy": function() {
                // Show loader
                $('.ui-dialog #imageCopyCd').append(createLoader(''));

                // Change dialog buttons
                $(this).dialog('option', 'buttons', {
                    'Close': function() {$(this).dialog("close");}
                });

                // Get image attributes
                var iso = $(this).find('input[name="iso"]');
                var arch = $(this).find('input[name="arch"]');
                var distro = $(this).find('input[name="distro"]');

                // Send ajax request to copy ISO
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'copycds',
                        tgt : '',
                        args : '-n;' + distro.val() + ';-a;' + arch.val() + ';' + iso.val(),
                        msg : dialogId
                    },

                    success : updateImageDialog
                });
            },
            "Cancel": function() {
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Use user input or select to create image
 */
function createImage() {
    var osvers = $("#createImageTab #osvers").val();
    var osarch = $("#createImageTab #osarch").val();
    var profile = $("#createImageTab #profile").val();
    var bootInterface = $("#createImageTab #netbootif").val();
    var bootMethod = $("#createImageTab #bootmethod").val();

    $('#createImageTab .ui-state-error').remove();
    // If there no input for the bootInterface
    if (!bootInterface) {
        var warnBar = createWarnBar('Please specify the netboot interface');
        $("#createImageTab").prepend(warnBar);
        return;
    }

    var createImageArgs = "createimage;" + osvers + ";" + osarch + ";" + profile + ";" + bootInterface + ";" + bootMethod + ";";

    $("#createImageTab :checkbox:checked").each(function() {
        createImageArgs += $(this).attr("name") + ",";
    });

    createImageArgs = createImageArgs.substring(0, (createImageArgs.length - 1));
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : createImageArgs,
            msg : ''
        },
        success : function(data) {

        }
    });
}
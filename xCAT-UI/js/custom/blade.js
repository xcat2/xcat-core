/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
    // Load utility scripts (if any)
});

/**
 * Constructor
 */
var bladePlugin = function() {

};

/**
 * Load node inventory
 *
 * @param data Data from HTTP request
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
 * @param node Source node to clone
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
 * @param tabId The provision tab ID
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
 */
bladePlugin.prototype.loadResources = function() {
    // Get resource tab ID
    var tabId = 'bladeResourceTab';
    // Remove loader
    $('#' + tabId).find('img').remove();

    // Create info bar
    var infoBar = createInfoBar('Not yet supported');

    // Create resource form
    var resrcForm = $('<div class="form"></div>');
    resrcForm.append(infoBar);

    $('#' + tabId).append(resrcForm);
};

/**
 * Add node range
 */
bladePlugin.prototype.addNode = function() {
    var addNodeForm = $('<div id="addBladeCenter" class="form"></div>');
    var info = createInfoBar('Add a BladeCenter node');
    addNodeForm.append(info);

    var typeFS = $('<fieldset></fieldset>');
    var typeLegend = $('<legend>Type</legend>');
    typeFS.append(typeLegend);
    addNodeForm.append(typeFS);

    var settingsFS = $('<fieldset id="bcSettings"></fieldset>');
    var nodeLegend = $('<legend>Settings</legend>');
    settingsFS.append(nodeLegend);
    addNodeForm.append(settingsFS);

    typeFS.append('<div>' +
            '<label>Node type:</label>' +
            '<select id="typeSelect">' +
                '<option value="amm">AMM</option>' +
                '<option value="blade">Blade</option>' +
                '<option value="scan">Blade by scan</option>' +
            '</select>' +
    '</div>');

    // Change dialog width
    $('#addBladeCenter').dialog('option', 'width', '400');

    typeFS.find('#typeSelect').bind('change', function(){
        // Remove any existing warnings
        $('#addBladeCenter .ui-state-error').remove();
        settingsFS.find('div').remove();

        // Change dialog width
        $('#addBladeCenter').dialog('option', 'width', '400');

        var nodeType = $(this).val();
        switch (nodeType) {
            case 'amm':
                settingsFS.append('<div><label>AMM name:</label><input name="ammName" type="text"/></div>');
                settingsFS.append('<div><label>User name:</label><input name="ammUser" type="text"></div>');
                settingsFS.append('<div><label>Password:</label><input name="ammPassword" type="password"></div>');
                settingsFS.append('<div><label>IP address:</label><input id="ammIp" type="text"/></div>');
                break;
            case 'blade':
                settingsFS.append('<div><label>Blade name:</label><input name="bladeName" type="text"/></input></div>');
                settingsFS.append('<div><label>Blade group:</label><input name="bladeGroup" type="text"/></input></div>');
                settingsFS.append('<div><label>Blade ID:</label><input name="bladeId" type="text"/t></div>');
                settingsFS.append('<div><label>Blade series:</label>JS <input type="radio" name="bladeSeries" value="js"/> LS<input type="radio" name="bladeSeries" value="ls"/></div>');
                settingsFS.append('<div><label style="vertical-align: middle;">Blade MPA:</label><select name="bladeMpa"></select><div>');
                break;
            case 'scan':
                settingsFS.append('<div><label style="vertical-align: middle;">Blade MPA:</label><select id="bladeMpa"></select></div>');

                // Change dialog width
                $('#addBladeCenter').dialog('option', 'width', '650');
                break;
        }

        // Do not continue if node type is AMM
        if ($(this).val() == 'amm') {
            return;
        }

        // Gather AMM nodes
        settingsFS.find('select:eq(0)').after(createLoader());
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                   cmd : 'lsdef',
                   tgt : '',
                   args : '-t;node;-w;mgt==blade;-w;id==0',
                   msg : nodeType
               },
               success : function(data) {
                   var position = 0;
                   var tmp = '';
                   var options = '';

                   // Remove the loading image
                   settingsFS.find('img').remove();

                   // Do not continue if no AMM nodes are found
                   if (data.rsp.length < 1) {
                       $('#addBladeCenter').prepend(createWarnBar('Please define an AMM node before continuing'));
                       return;
                   }

                   // Create options for AMM nodes
                   for (var i in data.rsp){
                       tmp = data.rsp[i];
                       position = tmp.indexOf(' ');
                       tmp = tmp.substring(0, position);
                       options += '<option value="' + tmp + '">' + tmp + '</option>';
                   }

                   // Select the first AMM node
                   settingsFS.find('select:eq(0)').append(options);
                   if (data.msg != 'scan') {
                       return;
                   }

                   // Create Scan button
                   var scan = createButton('Scan');
                   scan.bind('click', function(){
                       var ammName = settingsFS.find('select:eq(0)').val();
                       settingsFS.prepend(createLoader());
                       $('#bcSettings button').attr('disabled', 'disabled');
                       $.ajax({
                           url : 'lib/cmd.php',
                           dataType : 'json',
                           data : {
                               cmd : 'rscan',
                               tgt : ammName,
                               args : '',
                               msg : ''
                           },

                           /**
                            * Show scanned results for AMM
                            *
                            * @param data Data returned from HTTP request
                            */
                           success: function(data){
                               showScanAmmResult(data.rsp[0]);
                           }
                       });
                   });

                   settingsFS.find('select:eq(0)').after(scan);
               }
        });
    });

    // Create dialog for BladeCenter
    addNodeForm.dialog({
        modal : true,
        width : 400,
        title : 'Add node',
        open : function(event, ui) {
            $(".ui-dialog-titlebar-close").hide();
        },
        close : function(){
            $(this).remove();
        },
        buttons : {
            'Ok' : function() {
                // Remove any existing warnings
                $('#addBladeCenter .ui-state-error').remove();
                var addMethod = $('#typeSelect').val();

                if (addMethod == "amm") {
                    addAmmNode();
                } else if(addMethod == "blade") {
                    addBladeNode();
                } else{
                    addMmScanNode();
                }
            },
            'Cancel' : function() {
                $(this).remove();
            }
        }
    });

    addNodeForm.find('#typeSelect').trigger('change');
};


/**
 * Add AMM node
 */
function addAmmNode(){
    var args = '';
    var errorMsg = '';

    // Check for missing inputs
    $('#addBladeCenter input').each(function(){
        if (!$(this).val()) {
            errorMsg = 'Please provide a value for each missing field!';
        }

        args += $(this).val() + ',';
    });

    // Do not continue if error was found
    if (errorMsg) {
        $('#addBladeCenter').prepend(createWarnBar(errorMsg));
        return;
    }

    args = args.substring(0, args.length - 1);

    // Add the loader
    $('#addBladeCenter').append(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;mm;' + args,
            msg : ''
        },
        success : function(data) {
            // Remove loader
            $('#addBladeCenter').find('img').remove();
            $('#addBladeCenter').prepend(createInfoBar('AMM node was successfully added'));
            $('#addBladeCenter').dialog("option", "buttons", {
                "Close" : function() {
                    $('#addBladeCenter').dialog('destroy').remove();
                }
            });
        }
    });
}

/**
 * Add blade node
 */
function addBladeNode(){
    // Get blade node attributes
    var name = $('#bcSettings input[name="bladeName"]').val();
    var group = $('#bcSettings input[name="bladeGroup"]').val();
    var id = $('#bcSettings input[name="bladeId"]').val();
    var series = $('#bcSettings input[name="bladeSeries"]:selected').val();
    var mpa = $('#bcSettings select[name="bladeMpa"]').val();

    var args = '-t;node;-o;' + name
        + ';id=' + id
        + ';nodetype=osi;groups=' + group
        + ';mgt=blade;mpa=' + mpa
        + ';serialflow=hard';

    // Set the serial speed and port for LS series blade
    if (series != 'js') {
        args += ';serialspeed=19200;serialport=1';
    }

    // Check for missing inputs
    if (!name || !group || !id || !mpa) {
        $('#addBladeCenter').prepend(createWarnBar("Please provide a value for each missing field!"));
        return;
    }

    // Add loader and disable buttons
    $('#addBladeCenter').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        },
        success : function(data) {
            // Remove loader
            $('#addBladeCenter').find('img').remove();

            // Gather response and display it
            var rsp = data.rsp;
            var rspMessage = '';
            for (var i = 0; i < rsp.length; i++) {
                rspMessage += rsp[i] + '<br/>';
            }

            // Append response message to dialog
            $('#addBladeCenter').prepend(createInfoBar(rspMessage));

            // Change dialog button
            $('#addBladeCenter').dialog("option", "buttons", {
                "Close" : function() {
                    $('#addBladeCenter').remove();
                }
            });
        }
    });
}

/**
 * Show rscan results
 *
 * @param results Results from rscan of blade MPA
 */
function showScanAmmResult(results){
    var rSection = $('<div style="height: 300px; overflow: auto;" id="scanResults"></div>');

    // Create table to hold results
    var rTable = $('<table></table>');

    // Reset scan results area
    $('#addBladeCenter #scanResults').remove();
    $('#bcSettings img').remove();
    $('#bcSettings button').attr('disabled', '');
    if (!results)
        return;

    // Do not continue if there are no results
    var rows = results.split("\n");
    if (rows.length < 2){
        $('#bcSettings').prepend(createWarnBar(rows[0]));
        return;
    }

    // Add the table header
    var fields = rows[0].match(/\S+/g);
    var column = fields.length;
    var row = $('<tr></tr>');
    row.append('<td><input type="checkbox" onclick="selectAllRscanNode(this)"></td>');
    for(var i in fields){
        row.append('<td>' + fields[i] + '</td>');
    }
    rTable.append(row);

    // Add table body
    var line;
    for (var i = 1; i < rows.length; i++) {
        line = rows[i];

        if (!line)
            continue;

        var fields = line.match(/\S+/g);
        if (fields[0] == 'mm')
            continue;

        // Create a row for each result
        var row = $('<tr></tr>');
        row.append('<td><input type="checkbox" name="' + fields[1] + '"></td>');

        // Add column for each field
        for (var j = 0; j < column; j++){
            if (fields[j]) {
                if (j == 1) {
                    row.append('<td><input value="' + fields[j] + '"></td>');
                } else {
                    row.append('<td>' + fields[j] + '</td>');
                }
            } else {
                row.append('<td></td>');
            }
        }

        // Append row to table
        rTable.append(row);
    }

    rSection.append(rTable);
    $('#bcSettings').prepend(rSection);
}

/**
 * Add AMM scanned node
 */
function addMmScanNode(){
    // Get the AMM name
    var ammName = $('#bcSettings select').val();
    var nodeName = '';

    $('#bcSettings :checked').each(function() {
        if ($(this).attr('name')) {
            nodeName += $(this).attr('name') + ',';
            nodeName += $(this).parents('tr').find('input').eq(1).val() + ',';
        }
    });

    if (!nodeName) {
        $('#addBladeCenter').prepend(createWarnBar('Please select a node!'));
        return;
    }

    // Disabled button
    $('.ui-dialog-buttonpane button').attr('disabled', 'disabled');

    nodeName = nodeName.substr(0, nodeName.length - 1);
    $('#nodeAttrs').append(createLoader());

    // Send add request
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'addnode;node;' + ammName + ',' + nodeName,
            msg : ''
        },
        success : function(data){
            $('#addBladeCenter').dialog('destroy').remove();
        }
    });
}

/**
 * Create provision existing node division
 *
 * @param inst Provision tab instance
 * @return Provision existing node division
 */
function createBladeProvisionExisting(inst) {
    // Create provision existing division
    var provExisting = $('<div></div>');

    // Create node fieldset
    var nodeFS = $('<fieldset></fieldset>');
    var nodeLegend = $('<legend>Node</legend>');
    nodeFS.append(nodeLegend);

    var nodeAttr = $('<div style="display: inline-table; vertical-align: middle; width: 85%; margin-left: 10px;"></div>');
    nodeFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    nodeFS.append(nodeAttr);

    // Create image fieldset
    var imgFS = $('<fieldset></fieldset>');
    var imgLegend = $('<legend>Image</legend>');
    imgFS.append(imgLegend);

    var imgAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imgFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
    imgFS.append(imgAttr);

    provExisting.append(nodeFS, imgFS);

    // Create group input
    var group = $('<div></div>');
    var groupLabel = $('<label>Group:</label>');
    group.append(groupLabel);

    // Turn on auto complete for group
    var dTableDivId = 'bladeNodesDatatableDIV' + inst;    // Division ID where nodes datatable will be appended
    var groupNames = $.cookie('xcat_groups');
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
    nodeAttr.append(group);

    // Create node input
    var node = $('<div></div>');
    var nodeLabel = $('<label>Nodes:</label>');
    var nodeDatatable = $('<div id="' + dTableDivId + '" style="display: inline-block; max-width: 800px;"><p>Select a group to view its nodes</p></div>');
    node.append(nodeLabel);
    node.append(nodeDatatable);
    nodeAttr.append(node);

    // Create boot method drop down
    var method = $('<div></div>');
    var methodLabel = $('<label>Boot method:</label>');
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
    imgAttr.append(method);

    // Create operating system input
    var os = $('<div></div>');
    var osLabel = $('<label>Operating system:</label>');
    var osInput = $('<input type="text" name="os"/>');
    osInput.one('focus', function() {
        var tmp = $.cookie('xcat_osvers');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    os.append(osLabel);
    os.append(osInput);
    imgAttr.append(os);

    // Create architecture input
    var arch = $('<div></div>');
    var archLabel = $('<label>Architecture:</label>');
    var archInput = $('<input type="text" name="arch"/>');
    archInput.one('focus', function() {
        var tmp = $.cookie('xcat_osarchs');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    arch.append(archLabel);
    arch.append(archInput);
    imgAttr.append(arch);

    // Create profile input
    var profile = $('<div></div>');
    var profileLabel = $('<label>Profile:</label>');
    var profileInput = $('<input type="text" name="profile"/>');
    profileInput.one('focus', function() {
        var tmp = $.cookie('xcat_profiles');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    profile.append(profileLabel);
    profile.append(profileInput);
    imgAttr.append(profile);

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
                    args : tgts + ';noderes.netboot=xnba;nodetype.os=' + os.val() + ';nodetype.arch=' + arch.val() + ';nodetype.profile=' + profile.val() + ';nodetype.provmethod=' + boot.val(),
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
 * Update the provision existing node status
 *
 * @param data Data returned from HTTP request
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
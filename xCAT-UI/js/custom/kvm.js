/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
    // Load utility scripts (if any)
});

/**
 * Constructor
 */
var kvmPlugin = function() {

};

/**
 * Configure self-service page
 */
kvmPlugin.prototype.loadConfigPage = function(tabId) {
    var configAccordion = $('<div id="kvmConfigAccordion"></div>');

    // Create accordion panel for profiles
    var profileSection = $('<div id="kvmConfigProfile"></div>');
    var profileLnk = $('<h3><a href="#">Profiles</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#kvmConfigProfile').find('.dataTables_wrapper').length)
            return;
        else
            $('#kvmConfigProfile').append(createLoader(''));

        // Wipe panel clean
        $('#kvmConfigProfile').empty();

        // Add info bar
        $('#kvmConfigProfile').append(createInfoBar('Not yet supported'));

        // Resize accordion
        configAccordion.accordion('resize');
    });

    // Create accordion panel for images
    var imgSection = $('<div id="kvmConfigImages"></div>');
    var imgLnk = $('<h3><a href="#">Images</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#kvmConfigImages').find('.dataTables_wrapper').length)
            return;
        else
            $('#kvmConfigImages').append(createLoader(''));

        queryImages('kvmConfigImages');
    });

    // Create accordion panel for groups
    var groupsSection = $('<div id="kvmConfigGroups"></div>');
    var groupsLnk = $('<h3><a href="#">Groups</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#kvmConfigGroups').find('.dataTables_wrapper').length)
            return;
        else
            $('#kvmConfigGroups').append(createLoader(''));

        queryGroups('kvmConfigGroups');
    });

    configAccordion.append(profileLnk, profileSection, imgLnk, imgSection, groupsLnk, groupsSection);
    $('#' + tabId).append(configAccordion);
    configAccordion.accordion();

    profileLnk.trigger('click');
};

/**
 * Migrate node
 *
 * @param node Node to migrate
 */
kvmPlugin.prototype.loadMigratePage = function(node) {
    openDialog('info', 'Not yet supported');
};

/**
 * Clone node (service page)
 *
 * @param node Node to clone
 */
kvmPlugin.prototype.serviceClone = function(node) {
    openDialog('info', 'Not yet supported');
};

/**
 * Load provision page (service page)
 *
 * @param tabId Tab ID where page will reside
 */
kvmPlugin.prototype.loadServiceProvisionPage = function(tabId) {
    $('#' + tabId).append(createInfoBar('Not yet supported'));
};

/**
 * Show node inventory (service page)
 *
 * @param data Data from HTTP request
 */
kvmPlugin.prototype.loadServiceInventory = function(data) {

};

/**
 * Load node inventory
 *
 * @param data Data from HTTP request
 */
kvmPlugin.prototype.loadInventory = function(data) {
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
        // Remove node name
        var attr = inv[k].replace(node + ': ', '');
        attr = jQuery.trim(attr);

        // Append attribute to list
        item = $('<li></li>');
        item.append(attr);
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
kvmPlugin.prototype.loadClonePage = function(node) {
    // Get nodes tab
    var tab = getNodesTab();
    var newTabId = node + 'CloneTab';

    // If there is no existing clone tab
    if (!$('#' + newTabId).length) {
        // Create info bar
        var infoBar = createInfoBar('Not yet supported');

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
kvmPlugin.prototype.loadProvisionPage = function(tabId) {
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

    // Create provision form
    var provForm = $('<div class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Provision an KVM virtual machine.');
    provForm.append(infoBar);

    // Append to provision tab
    $('#' + tabId).append(provForm);

    // Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);

    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);

    // Create hardware fieldset
    var hwFS = $('<fieldset></fieldset>');
    var hwLegend = $('<legend>Hardware</legend>');
    hwFS.append(hwLegend);

    var hwAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    hwFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/hardware.png"></img></div>'));
    hwFS.append(hwAttr);

    // Create image fieldset
    var imgFS = $('<fieldset></fieldset>');
    var imgLegend = $('<legend>Image</legend>');
    imgFS.append(imgLegend);

    var imgAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imgFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
    imgFS.append(imgAttr);

    provForm.append(vmFS, hwFS, imgFS);

    // Create hypervisor input
    var host = $('<div></div>');
    var hostLabel = $('<label>Host:</label>');
    host.append(hostLabel);
    var hostInput = $('<input type="text" name="host"/>');
    host.append(hostInput);
    vmAttr.append(host);

    // Create group input
    var group = $('<div></div>');
    var groupLabel = $('<label>Group:</label>');
    group.append(groupLabel);

    // Turn on auto complete for group
    var groupNames = $.cookie('xcat_groups');
    if (groupNames) {
        // Split group names into an array
        var tmp = groupNames.split(',');

        // Create drop down for groups
        var groupSelect = $('<select name="group"></select>');
        groupSelect.append('<option></option>');
        for ( var i in tmp) {
            // Add group into drop down
            var opt = $('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
            groupSelect.append(opt);
        }
        group.append(groupSelect);
    } else {
        // If no groups are cookied
        var groupInput = $('<input type="text" name="group"/>');
        group.append(groupInput);
    }
    vmAttr.append(group);

    // Create node input
    var node = $('<div></div>');
    var nodeLabel = $('<label>VM name:</label>');
    var nodeInput = $('<input type="text" name="node"/>');
    node.append(nodeLabel);
    node.append(nodeInput);
    vmAttr.append(node);

    // Create memory input
    var memory = $('<div></div>');
    var memoryLabel = $('<label>Memory:</label>');
    var memoryInput = $('<input type="text" name="memory" size="5"/>');
    memory.append(memoryLabel);
    memory.append(memoryInput);
    hwAttr.append(memory);

    // Create processor dropdown
    var cpu = $('<div></div>');
    var cpuLabel = $('<label>Processor:</label>');
    var cpuSelect = $('<select name="cpu"></select>');
    cpuSelect.append('<option value="1">1</option>'
        + '<option value="2">2</option>'
        + '<option value="3">3</option>'
        + '<option value="4">4</option>'
        + '<option value="5">5</option>'
        + '<option value="6">6</option>'
        + '<option value="7">7</option>'
        + '<option value="8">8</option>'
    );
    cpu.append(cpuLabel);
    cpu.append(cpuSelect);
    hwAttr.append(cpu);

    // Create NIC dropdown
    var nic = $('<div></div>');
    var nicLabel = $('<label>NIC:</label>');
    var nicInput = $('<input type="text" name="nic"/>');
    nic.append(nicLabel);
    nic.append(nicInput);
    hwAttr.append(nic);

    // Create disk input
    var disk = $('<div></div>');
    var diskLabel = $('<label>Disk size:</label>');
    var diskInput = $('<input type="text" name="disk" size="5"/>');
    var diskSizeSelect = $('<select name="diskUnit"></select>');
    diskSizeSelect.append('<option value="G">GB</option>' +
        '<option value="M">MB</option>'
    );
    disk.append(diskLabel, diskInput, diskSizeSelect);
    hwAttr.append(disk);

    // Create disk storage input
    var storage = $('<div></div>');
    var storageLabel = $('<label>Storage:</label>');
    var storageInput = $('<input type="text" name="storage"/>');
    storage.append(storageLabel);
    storage.append(storageInput);
    hwAttr.append(storage);

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

    // Create boot method dropdown
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

    /**
     * Provision existing
     */
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(event) {
        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
        var ready = true;

        // Get tab ID
        var tabId = $(this).parents('.ui-tabs-panel').attr('id');

        // Check if fields are properly filled in
        var inputs = $('#' + tabId + ' input:visible');
        for ( var i = 0; i < inputs.length; i++) {
            if (!inputs.eq(i).val() && inputs.eq(i).attr('name') != 'storage') {
                inputs.eq(i).css('border', 'solid #FF0000 1px');
                ready = false;
            } else {
                inputs.eq(i).css('border', 'solid #BDBDBD 1px');
            }
        }

        var selects = $('#' + tabId + ' select:visible');
        for ( var i = 0; i < selects.length; i++) {
            if (!selects.eq(i).val()) {
                selects.eq(i).css('border', 'solid #FF0000 1px');
                ready = false;
            } else {
                selects.eq(i).css('border', 'solid #BDBDBD 1px');
            }
        }

        if (ready) {
            var inst = tabId.replace('kvmProvisionTab', '');

            // Prepend status bar
            var statBar = createStatusBar('kvmProvisionStatBar' + inst);
            statBar.append(createLoader(''));
            statBar.prependTo($('#' + tabId));

            var host = $('#' + tabId + ' input[name=host]').val();
            var group = $('#' + tabId + ' select[name=group]').val();
            var node = $('#' + tabId + ' input[name=node]').val();

            var memory = $('#' + tabId + ' input[name=memory]').val();
            var cpu = $('#' + tabId + ' select[name=cpu]').val();
            var nic = $('#' + tabId + ' input[name=nic]').val();
            var disk = $('#' + tabId + ' input[name=disk]').val() + $('#' + tabId + ' select[name=diskUnit]').val();
            var storage = $('#' + tabId + ' input[name=storage]').val();

            var os = $('#' + tabId + ' input[name=os]').val();
            var arch = $('#' + tabId + ' input[name=arch]').val();
            var profile = $('#' + tabId + ' input[name=profile]').val();
            var boot = $('#' + tabId + ' select[name=bootMethod]').val();

            /**
             * (1) Define node
             */
            var args = '-t;node;-o;' + node +
                ';vmhost=' + host +
                ';groups=' + group +
                ';vmmemory=' + memory +
                ';vmcpus=' + cpu +
                ';vmnics=' + nic +
                ';vmstorage=' + storage +
                ';os=' + os +
                ';arch=' + arch +
                ';profile=' + profile +
                ';netboot=xnba' +
                ';nodetype=osi' +
                ';serialport=0' +
                ';serialspeed=115200' +
                ';mgt=kvm';
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'chdef',
                    tgt : '',
                    args : args,
                    msg : 'cmd=chdef;out=' + inst
                },

                success : updateKVMProvisionStatus
            });
        } else {
            // Show warning message
            var warn = createWarnBar('Please provide a value for each missing field.');
            warn.prependTo($(this).parent().parent());
        }
    });
    provForm.append(provisionBtn);
};

/**
 * Load resources
 */
kvmPlugin.prototype.loadResources = function() {
    // Get resource tab ID
    var tabId = 'kvmResourceTab';
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
kvmPlugin.prototype.addNode = function() {
    var dialog = $('<div id="addKvm" class="form"></div>');
    var info = createInfoBar('Add a KVM node');
    dialog.append(info);

    // Create node inputs
    dialog.append($('<div><label>Node:</label><input name="node" type="text"></div>'));
    dialog.append($('<div><label>VM host:</label><input name="vmhost" type="text"></div>'));
    dialog.append($('<div><label>IP address:</label><input name="ip" type="text"></div>'));
    dialog.append($('<div><label>Groups:</label><input name="groups" type="text"></div>'));

    dialog.dialog({
        title: 'Add node',
        modal: true,
        width: 400,
        close: function(){$(this).remove();},
        buttons: {
            "OK" : function(){addKvmNode();},
            "Cancel": function(){$(this).dialog('destroy').remove();}
        }
    });
};

/**
 * Add iDataPlex node range
 */
function addKvmNode(){
    var attr, args;
    var errorMessage = '';

    // Remove existing warnings
    $('#addKvm .ui-state-error').remove();

    // Return input border colors to normal
    $('#addKvm input').css('border', 'solid #BDBDBD 1px');

    // Check node attributes
    $('#addKvm input').each(function(){
        attr = $(this).val();
        if (!attr) {
            errorMessage = "Please provide a value for each missing field!";
            $(this).css('border', 'solid #FF0000 1px');
        }
    });

    // Show error message (if any)
    if (errorMessage) {
        $('#addKvm').prepend(createWarnBar(errorMessage));
        return;
    }

    // Create loader
    $('#addKvm').append(createLoader());

    // Change dialog buttons
    $('#addKvm').dialog('option', 'buttons', {
        'Close':function(){
            $('#addKvm').dialog('destroy').remove();
        }
    });

    // Generate chdef arguments
    args = '-t;node;-o;' + $('#addKvm input[name="node"]').val()
        + ';ip=' + $('#addKvm input[name="ip"]').val()
        + ';groups=' + $('#addKvm input[name="groups"]').val()
        + ';vmhost=' + $('#addKvm input[name="vmhost"]').val()
        + ';mgt=kvm;netboot=xnba;nodetype=osi;profile=compute';
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        },
        success: function(data) {
            // Update /etc/hosts
            $.ajax({
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'makehosts',
                    tgt : '',
                    args : '',
                    msg : ''
                }
            });

            // Remove loader
            $('#addKvm img').remove();

            // Get return message
            var message = '';
            for (var i in data.rsp) {
                message += data.rsp[i] + '<br/>';
            }

            // Show return message
            if (message)
                $('#addKvm').prepend(createInfoBar(message));
        }
    });
}

/**
 * Update the provision node status
 *
 * @param data Data returned from HTTP request
 */
function updateKVMProvisionStatus(data) {
    // Get ajax response
    var rsp = data.rsp;
    var args = data.msg.split(';');

    // Get command invoked
    var cmd = args[0].replace('cmd=', '');
    // Get provision tab instance
    var inst = args[1].replace('out=', '');

    // Get provision tab and status bar ID
    var statBarId = 'kvmProvisionStatBar' + inst;
    var tabId = 'kvmProvisionTab' + inst;

    var node = $('#' + tabId + ' input[name=node]').val();

    /**
     * (2) Create virtual machine
     */
    if (cmd == 'chdef') {
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);

        // Get parameters
        var disk = $('#' + tabId + ' input[name=disk]').val() + $('#' + tabId + ' select[name=diskUnit]').val();

        // Begin installation
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'mkvm',
                tgt : '',
                args : node + ';-s;' + disk,
                msg : 'cmd=mkvm;out=' + inst
            },

            success : updateKVMProvisionStatus
        });
    }

    /**
     * (3) Prepare node for boot
     */
    if (cmd == 'mkvm') {
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);

        // Get provision method
        var boot = $('#' + tabId + ' select[name=bootMethod]').val();

        // Prepare node for boot
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'nodeset',
                tgt : node,
                args : boot,
                msg : 'cmd=nodeset;out=' + inst
            },

            success : updateKVMProvisionStatus
        });
    }

    /**
     * (4) Power on node
     */
    if (cmd == 'nodeset') {
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);

        // Prepare node for boot
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'rpower',
                tgt : node,
                args : 'on',
                msg : 'cmd=rpower;out=' + inst
            },

            success : updateKVMProvisionStatus
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

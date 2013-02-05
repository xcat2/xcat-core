/**
 * Load nodeset page
 * 
 * @param tgtNodes Targets to run nodeset against
 */
function loadNodesetPage(tgtNodes) {
    // Get OS images
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

    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var tabId = 'nodesetTab' + inst;
    while ($('#' + tabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        tabId = 'nodesetTab' + inst;
    }
    
    // Create nodeset form
    var nodesetForm = $('<div class="form"></div>');

    // Create status bar
    var statBarId = 'nodesetStatusBar' + inst;
    var statBar = createStatusBar(statBarId).hide();

    // Create loader
    var loader = createLoader('nodesetLoader');
    statBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Set the boot state for a node range');
    nodesetForm.append(statBar, infoBar);
    
	// Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);
    nodesetForm.append(vmFS);
    
    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);
    
	// Create options fieldset
    var imageFS = $('<fieldset></fieldset>');
    var imageLegend = $('<legend>Image</legend>');
    imageFS.append(imageLegend);
    nodesetForm.append(imageFS);
    
    var imageAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imageFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>'));
    imageFS.append(imageAttr);

    // Create target node or group
    var tgt = $('<div><label>Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to set the boot state for"/></div>');
    vmAttr.append(tgt);

    // Create boot method drop down
    var method = $('<div></div>');
    var methodLabel = $('<label>Boot method:</label>');
    var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
    methodSelect.append('<option value="boot">boot</option>'
        + '<option value="install">install</option>'
        + '<option value="iscsiboot">iscsiboot</option>'
        + '<option value="netboot">netboot</option>'
        + '<option value="statelite">statelite</option>'
    );
    method.append(methodLabel);
    method.append(methodSelect);
    imageAttr.append(method);

    // Create boot type drop down
    var type = $('<div></div>');
    var typeLabel = $('<label>Boot type:</label>');
    var typeSelect = $('<select id="bootType" name="bootType"></select>');
    typeSelect.append('<option value="zvm">zvm</option>'
        + '<option value="install">pxe</option>'
        + '<option value="iscsiboot">yaboot</option>'
    );
    type.append(typeLabel);
    type.append(typeSelect);
    imageAttr.append(type);

    // Create operating system input
    var os = $('<div></div>');
    var osLabel = $('<label>Operating system:</label>');
    var osInput = $('<input type="text" name="os" title="You must give the operating system of this node or node range, e.g. rhel5.5"/>');
    osInput.one('focus', function(){
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
    imageAttr.append(os);

    // Create architecture input
    var arch = $('<div></div>');
    var archLabel = $('<label>Architecture:</label>');
    var archInput = $('<input type="text" name="arch" title="You must give the architecture of this node or node range, e.g. s390x"/>');
    archInput.one('focus', function(){
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
    imageAttr.append(arch);

    // Create profiles input
    var profile = $('<div></div>');
    var profileLabel = $('<label>Profile:</label>');
    var profileInput = $('<input type="text" name="profile" title="You must give the profile for this node or node range.  The typical default profile is: compute."/>');
    profileInput.one('focus', function(){
        tmp = $.cookie('profiles');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    profile.append(profileLabel);
    profile.append(profileInput);
    imageAttr.append(profile);

    // Generate tooltips
    nodesetForm.find('div input[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.7,
        predelay: 800,
        events : {
            def : "mouseover,mouseout",
            input : "mouseover,mouseout",
            widget : "focus mouseover,blur mouseout",
            tooltip : "mouseover,mouseout"
        }
    });
    
    /**
     * Ok
     */
    var okBtn = createButton('Ok');
    okBtn.css({
    	'width': '80px',
    	'display': 'block'
    });
    okBtn.bind('click', function(event) {
    	// Remove any warning messages
    	$(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
        
        // Check state, OS, arch, and profile
        var ready = true;
        var inputs = $('#' + tabId + ' input');
        for ( var i = 0; i < inputs.length; i++) {
            if (!inputs.eq(i).val() && inputs.eq(i).attr('name') != 'diskPw') {
                inputs.eq(i).css('border', 'solid #FF0000 1px');
                ready = false;
            } else {
                inputs.eq(i).css('border', 'solid #BDBDBD 1px');
            }
        }

        if (ready) {
            // Get nodes
            var tgts = $('#' + tabId + ' input[name=target]').val();
            // Get boot method
            var method = $('#' + tabId + ' select[id=bootMethod]').val();
            // Get boot type
            var type = $('#' + tabId + ' select[id=bootType]').val();

            // Get OS, arch, and profile
            var os = $('#' + tabId + ' input[name=os]').val();
            var arch = $('#' + tabId + ' input[name=arch]').val();
            var profile = $('#' + tabId + ' input[name=profile]').val();

            // Disable all inputs, selects, and Ok button
            inputs.attr('disabled', 'disabled');
            $('#' + tabId + ' select').attr('disabled', 'disabled');
            $(this).attr('disabled', 'true');

            /**
             * (1) Set the OS, arch, and profile
             */
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'nodeadd',
                    tgt : '',
                    args : tgts + ';noderes.netboot=' + type 
                        + ';nodetype.os=' + os 
                        + ';nodetype.arch=' + arch 
                        + ';nodetype.profile=' + profile,
                    msg : 'cmd=nodeadd;inst=' + inst
                },

                success : updateNodesetStatus
            });

            // Show status bar
            statBar.show();
        } else {
            // Show warning message
            var warn = createWarnBar('You are missing some values!');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
        }
    });
    nodesetForm.append(okBtn);

    // Append to discover tab
    tab.add(tabId, 'Nodeset', nodesetForm, true);

    // Select new tab
    tab.select(tabId);
}

/**
 * Update nodeset status
 * 
 * @param data Data returned from HTTP request
 */
function updateNodesetStatus(data) {
    // Get ajax response
    var rsp = data.rsp;
    var args = data.msg.split(';');
    var cmd = args[0].replace('cmd=', '');

    // Get nodeset instance
    var inst = args[1].replace('inst=', '');
    // Get status bar ID
    var statBarId = 'nodesetStatusBar' + inst;
    // Get tab ID
    var tabId = 'nodesetTab' + inst;

    // Get nodes
    var tgts = $('#' + tabId + ' input[name=target]').val();
    // Get boot method
    var method = $('#' + tabId + ' select[id=bootMethod]').val();

    /**
     * (2) Update /etc/hosts
     */
    if (cmd == 'nodeadd') {
        if (rsp.length) {
            $('#' + statBarId).find('img').hide();
            $('#' + statBarId).find('div').append('<pre>(Error) Failed to create node definition</pre>');
        } else {
            // Create target nodes string
            var tgtNodesStr = '';
            var nodes = tgts.split(',');
            
            // Loop through each node
            for ( var i in nodes) {
                // If it is the 1st and only node
                if (i == 0 && i == nodes.length - 1) {
                    tgtNodesStr += nodes[i];
                }
                // If it is the 1st node of many nodes
                else if (i == 0 && i != nodes.length - 1) {
                    // Append a comma to the string
                    tgtNodesStr += nodes[i] + ', ';
                } else {
                    // If it is the last node
                    if (i == nodes.length - 1) {
                        // Append nothing to the string
                        tgtNodesStr += nodes[i];
                    } else {
                        // Append a comma to the string
                        tgtNodesStr += nodes[i] + ', ';
                    }
                }
            }
            
            $('#' + statBarId).find('div').append('<pre>Node definition created for ' + tgtNodesStr + '</pre>');
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'makehosts',
                    tgt : '',
                    args : '',
                    msg : 'cmd=makehosts;inst=' + inst
                },

                success : updateNodesetStatus
            });
        }
    }

    /**
     * (4) Update DNS
     */
    else if (cmd == 'makehosts') {
        // If no output, no errors occurred
        if (rsp.length) {
            $('#' + statBarId).find('div').append('<pre>(Error) Failed to update /etc/hosts</pre>');
        } else {
            $('#' + statBarId).find('div').append('<pre>/etc/hosts updated</pre>');
        }

        // Update DNS
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'makedns',
                tgt : '',
                args : '',
                msg : 'cmd=makedns;inst=' + inst
            },

            success : updateNodesetStatus
        });
    }

    /**
     * (5) Update DHCP
     */
    else if (cmd == 'makedns') {
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');    
        $('#' + statBarId).find('div').append(prg);    
        
        // Update DHCP
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'makedhcp',
                tgt : '',
                args : '-a',
                msg : 'cmd=makedhcp;inst=' + inst
            },

            success : updateNodesetStatus
        });
    }

    /**
     * (6) Prepare node for boot
     */
    else if (cmd == 'makedhcp') {
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');    
        $('#' + statBarId).find('div').append(prg);    

        // Prepare node for boot
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'nodeset',
                tgt : tgts,
                args : method,
                msg : 'cmd=nodeset;inst=' + inst
            },

            success : updateNodesetStatus
        });
    }

    /**
     * (7) Boot node from network
     */
    else if (cmd == 'nodeset') {
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');    
        $('#' + statBarId).find('div').append(prg);    

        // Hide loader
        $('#' + statBarId).find('img').hide();
    }
}
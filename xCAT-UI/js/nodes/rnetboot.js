/**
 * Load netboot page
 *
 * @param tgtNodes Targets to run rnetboot against
 */
function loadNetbootPage(tgtNodes) {
    // Get node OS
    var osHash = new Object();
    var nodes = tgtNodes.split(',');
    for (var i in nodes) {
        var os = getNodeAttr(nodes[i], 'os');
        var osBase = os.match(/[a-zA-Z]+/);
        if (osBase) {
            nodes[osBase] = 1;
        }
    }

    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'netbootTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'netbootTab' + inst;
    }

	// Create netboot form
    var netbootForm = $('<div class="form"></div>');

    // Create status bar
    var statBarId = 'netbootStatusBar' + inst;
    var statusBar = createStatusBar(statBarId).hide();

    // Create loader
    var loader = createLoader('netbootLoader');
    statusBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Cause the range of nodes to boot to network');
    netbootForm.append(statusBar, infoBar);

	// Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);
    netbootForm.append(vmFS);

    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);

	// Create options fieldset
    var optionsFS = $('<fieldset></fieldset>');
    var optionsLegend = $('<legend>Options</legend>');
    optionsFS.append(optionsLegend);
    netbootForm.append(optionsFS);

    var optionsAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    optionsFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>'));
    optionsFS.append(optionsAttr);

    // Create target node or group input
    var target = $('<div><label>Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to boot to network"/></div>');
    vmAttr.append(target);

    // Create options
    var optsLabel = $('<label>Options:</label>');
    var optsList = $('<ul></ul>');
    optionsAttr.append(optsList);

    // Create boot order checkbox
    var opt = $('<li></li>');
    var bootOrderChkBox = $('<input type="checkbox" id="s" name="s"/>');
    opt.append(bootOrderChkBox);
    opt.append('Set the boot device order');
    optsList.append(opt);
    // Create boot order input
    var bootOrder = $('<li><label>Boot order:</label><input type="text" name="bootOrder"/></li>');
    bootOrder.hide();
    optsList.append(bootOrder);

    // Create force reboot checkbox
    optsList.append('<li><input type="checkbox" id="F" name="F"/>Force reboot</li>');
    // Create force shutdown checkbox
    optsList.append('<li><input type="checkbox" id="f" name="f"/>Force immediate shutdown of the partition</li>');
    if (osHash['AIX']) {
        // Create iscsi dump checkbox
        optsList.append('<li><input type="checkbox" id="I" name="I"/>Do a iscsi dump on AIX</li>');
    }

    // Show boot order when checkbox is checked
    bootOrderChkBox.bind('click', function(event) {
        if ($(this).is(':checked')) {
            bootOrder.show();
        } else {
            bootOrder.hide();
        }
    });

    // Determine plugin
    var tmp = tgtNodes.split(',');
    for ( var i = 0; i < tmp.length; i++) {
        var mgt = getNodeAttr(tmp[i], 'mgt');
        // If it is zvm
        if (mgt == 'zvm') {
            // Add IPL input
        	optsList.append('<div><label style="width: 40px;">IPL:</label><input type="text" name="ipl" title="The virtual address to IPL"/></div>');
            break;
        }
    }

    // Generate tooltips
    netbootForm.find('div input[title]').tooltip({
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

        // Check inputs
        var ready = true;
        var inputs = $("#" + newTabId + " input[type='text']:visible");
        for ( var i = 0; i < inputs.length; i++) {
            if (!inputs.eq(i).val()) {
                inputs.eq(i).css('border', 'solid #FF0000 1px');
                ready = false;
            } else {
                inputs.eq(i).css('border', 'solid #BDBDBD 1px');
            }
        }

        // Generate arguments
        var chkBoxes = $("#" + newTabId + " input[type='checkbox']:checked");
        var optStr = '';
        var opt;
        for ( var i = 0; i < chkBoxes.length; i++) {
            opt = chkBoxes.eq(i).attr('name');
            optStr += '-' + opt;

            // If it is the boot order
            if (opt == 's') {
                // Get the boot order
                optStr += ';' + $('#' + newTabId + ' input[name=bootOrder]').val();
            }

            // Append ; to end of string
            if (i < (chkBoxes.length - 1)) {
                optStr += ';';
            }
        }

        // If no inputs are empty
        if (ready) {
            // Get nodes
            var tgts = $('#' + newTabId + ' input[name=target]').val();

            // Get IPL address
            var ipl = $('#' + newTabId + ' input[name=ipl]');
            if (ipl) {
                optStr += 'ipl=' + ipl.val();
            }

            // Disable all inputs and Ok button
            $('#' + newTabId + ' input').attr('disabled', 'disabled');
            $(this).attr('disabled', 'true');

            /**
             * (1) Boot to network
             */
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'rnetboot',
                    tgt : tgts,
                    args : optStr,
                    msg : 'out=' + statBarId + ';cmd=rnetboot;tgt=' + tgts
                },

                success : function(data) {
                    data = decodeRsp(data);
                    updateStatusBar(data);
                }
            });

            // Show status bar
            statusBar.show();
        } else {
            // Show warning message
            var warn = createWarnBar('Please provide a value for each missing field.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
        }
    });
    netbootForm.append(okBtn);

    // Append to discover tab
    tab.add(newTabId, 'Boot', netbootForm, true);

    // Select new tab
    tab.select(newTabId);
}
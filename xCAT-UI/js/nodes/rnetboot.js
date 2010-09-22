/**
 * Load netboot page
 * 
 * @param tgtNodes
 *            Targets to run rnetboot against
 * @return Nothing
 */
function loadNetbootPage(tgtNodes) {
	// Get node OS (AIX, rh*, centos*, fedora*, or sles*)
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
	var barId = 'netbootStatusBar' + inst;
	var statusBar = createStatusBar(barId);
	statusBar.hide();
	netbootForm.append(statusBar);

	// Create loader
	var loader = createLoader('netbootLoader');
	statusBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Cause the range of nodes to boot to network');
	netbootForm.append(infoBar);

	// Create target node or group input
	var target = $('<div><label for="target">Target node range:</label><input type="text" name="target" value="' + tgtNodes + '"/></div>');
	netbootForm.append(target);

	// Create options
	var optsDIV = $('<div></div>');
	var optsLabel = $('<label>Options:</label>');	
	var optsList = $('<ul></ul>');
	var opt = $('<li></li>');
	optsList.append(opt);
	optsDIV.append(optsLabel);
	optsDIV.append(optsList);
	netbootForm.append(optsDIV);
	
	// Create boot order checkbox
	var bootOrderChkBox = $('<input type="checkbox" id="s" name="s"/>');
	opt.append(bootOrderChkBox);
	opt.append('Set the boot device order');
	// Create boot order input
	var bootOrder = $('<li><label for="bootOrder">Boot order:</label><input type="text" name="bootOrder"/></li>');
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
			netbootForm.append('<div><label for="ipl">IPL:</label><input type="text" name="ipl"/></div>');
			break;
		}
	}

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
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

			// Disable Ok button
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
					msg : 'out=' + barId + ';cmd=rnetboot;tgt=' + tgts
				},

				success : updateStatusBar
			});

			// Show status bar
			statusBar.show();
		} else {
			alert('You are missing some values');
		}
	});
	netbootForm.append(okBtn);

	// Append to discover tab
	tab.add(newTabId, 'Netboot', netbootForm, true);

	// Select new tab
	tab.select(newTabId);
}
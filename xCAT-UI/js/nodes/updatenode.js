/**
 * Load updatenode page
 * 
 * @param tgtNodes
 *            Targets to run updatenode against
 * @return Nothing
 */
function loadUpdatenodePage(tgtNodes) {
	// Get nodes tab
	var tab = getNodesTab();

	// Generate new tab ID
	var inst = 0;
	var newTabId = 'updatenodeTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'updatenodeTab' + inst;
	}

	// Create updatenode form
	var updatenodeForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'updatenodeStatusBar' + inst;
	var statusBar = createStatusBar(statBarId);
	statusBar.hide();
	updatenodeForm.append(statusBar);

	// Create loader
	var loader = createLoader('updatenodeLoader');
	statusBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Update nodes in an xCAT environment');
	updatenodeForm.append(infoBar);

	// Create target node or group input
	var target = $('<div><label for="target">Target node or group:</label><input type="text" name="target" value="' + tgtNodes + '"/></div>');
	updatenodeForm.append(target);

	// Create options
	var optsDIV = $('<div></div>');
	var optsLabel = $('<label>Options:</label>');	
	var optsList = $('<ul></ul>');
	optsDIV.append(optsLabel);
	optsDIV.append(optsList);
	updatenodeForm.append(optsDIV);
		
	// Create update all software checkbox
	var updateAllChkBox = $('<input type="checkbox" id="A" name="A"/>');
	var updateAllOpt = $('<li></li>');
	optsList.append(updateAllOpt);
	updateAllOpt.append(updateAllChkBox);
	updateAllOpt.append('Install or update all software contained in the source directory');
	var allSwScrDirectory = $('<li><label for="allSwSrcDirectory">Alternate source directory:</label><input type="text" name="allSwSrcDirectory"/></li>');
	allSwScrDirectory.hide();
	optsList.append(allSwScrDirectory);
			
	// Show alternate source directory when checked
	updateAllChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			allSwScrDirectory.show();
		} else {
			allSwScrDirectory.hide();
		}
	});
	
	// Create update software checkbox
	var updateChkBox = $('<input type="checkbox" id="S" name="S"/>');
	var updateOpt = $('<li></li>');
	optsList.append(updateOpt);
	updateOpt.append(updateChkBox);
	updateOpt.append('Update software');
		
	// Create source directory input
	var scrDirectory = $('<li><label for="srcDirectory">Alternate source directory:</label><input type="text" name="srcDirectory"/></li>');
	scrDirectory.hide();
	optsList.append(scrDirectory);
	
	// Create other packages input
	var otherPkgs = $('<li><label for="otherpkgs">otherpkgs:</label><input type="text" name="otherpkgs"/></li>');
	otherPkgs.hide();
	optsList.append(otherPkgs);
	
	// Create RPM flags input
	var rpmFlags = $('<li><label for="rpm_flags">rpm_flags:</label><input type="text" name="rpm_flags"/></li>');
	rpmFlags.hide();
	optsList.append(rpmFlags);
	
	// Create installp flags input
	var installPFlags = $('<li><label for="installp_flags">installp_flags:</label><input type="text" name="installp_flags"/></li>');
	installPFlags.hide();
	optsList.append(installPFlags);
	
	// Show alternate source directory when checked
	updateChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			scrDirectory.show();
			otherPkgs.show();
			rpmFlags.show();
			installPFlags.show();
		} else {
			scrDirectory.hide();
			otherPkgs.hide();
			rpmFlags.hide();
			installPFlags.hide();
		}
	});
	
	// Create postscripts input
	var postChkBox = $('<input type="checkbox" id="P" name="P"/>');
	var postOpt = $('<li></li>');
	optsList.append(postOpt);
	postOpt.append(postChkBox);
	postOpt.append('Run postscripts');
	var postscripts = $('<li><label for="postscripts">Postscripts:</label><input type="text" name="postscripts"/></li>');
	postscripts.hide();
	optsList.append(postscripts);
	// Show alternate source directory when checked
	postChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			postscripts.show();
		} else {
			postscripts.hide();
		}
	});
	optsList.append('<li><input type="checkbox" id="F" name="F"/>Distribute and synchronize files</li>');
	optsList.append('<li><input type="checkbox" id="k" name="k"/>Update the ssh keys and host keys for the service nodes and compute nodes</li>');
	
	// Create update OS checkbox
	var osChkBox = $('<input type="checkbox" id="o" name="o"/>');
	var osOpt = $('<li></li>');
	optsList.append(osOpt);
	osOpt.append(osChkBox);
	osOpt.append('Update the operating system');
	var os = $('<li><label for="scripts">Operating system:</label><input type="text" name="os"/></li>');
	os.hide();
	optsList.append(os);
	
	// Show alternate source directory when checked
	osChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			os.show();
		} else {
			os.hide();
		}
	});
	
	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		var ready = true;
		
		// Generate arguments
		var chkBoxes = $("#" + newTabId + " input[type='checkbox']:checked");
		var optStr = '';
		var opt;
		for ( var i = 0; i < chkBoxes.length; i++) {
			opt = chkBoxes.eq(i).attr('name');
			optStr += '-' + opt;
			
			// If update all software is checked
			if (opt == 'S') {
				var srcDir = $('#' + newTabId + ' input[name=allSwSrcDirectory]').val();
				if (srcDir) {
					optStr += ';-d ' + srcDir;
				}				
			}
			
			// If update software is checked
			if (opt == 'S') {
				var srcDir = $('#' + newTabId + ' input[name=srcDirectory]').val();
				if (srcDir) {
					optStr += ';-d;' + srcDir;
				}
				
				var otherpkgs = $('#' + newTabId + ' input[name=otherpkgs]').val();
				if (otherpkgs) {
					optStr += ';otherpkgs=' + otherpkgs;
				}
				
				var rpm_flags = $('#' + newTabId + ' input[name=rpm_flags]').val();
				if (rpm_flags) {
					optStr += ';rpm_flags=' + rpm_flags;
				}
				
				var installp_flags = $('#' + newTabId + ' input[name=installp_flags]').val();
				if (installp_flags) {
					optStr += ';installp_flags=' + installp_flags;
				}
			}
			
			// If postscripts is checked
			if (opt == 'P') {
				// Get postscripts
				optStr += ';' + $('#' + newTabId + ' input[name=postscripts]').val();
			}
			
			// If operating system is checked
			if (opt == 'o') {
				// Get the OS
				optStr += ';' + $('#' + newTabId + ' input[name=os]').val();
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

			// Disable Ok button
			$(this).unbind(event);
			$(this).css( {
				'background-color' : '#F2F2F2',
				'color' : '#424242'
			});

			/**
			 * (1) Boot to network
			 */
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'updatenode',
					tgt : tgts,
					args : optStr,
					msg : 'out=' + statBarId + ';cmd=updatenode;tgt=' + tgts
				},

				success : updateStatusBar
			});

			// Show status bar
			statusBar.show();
		} else {
			alert('You are missing some values');
		}
	});
	updatenodeForm.append(okBtn);

	// Append to discover tab
	tab.add(newTabId, 'Updatenode', updatenodeForm, true);

	// Select new tab
	tab.select(newTabId);
}
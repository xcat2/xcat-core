/**
 * Load updatenode page
 * 
 * @param tgtNodes
 *            Targets to run updatenode against
 * @return Nothing
 */
function loadUpdatenodePage(tgtNodes) {
	// Get OS images
	$.ajax({
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
	var statusBar = createStatusBar(statBarId).hide();
	updatenodeForm.append(statusBar);

	// Create loader
	var loader = createLoader('updatenodeLoader');
	statusBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Update nodes in an xCAT environment');
	updatenodeForm.append(infoBar);
	
	// Create target node or group input
	var tgt = $('<div><label for="target">Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to update"/></div>');
	updatenodeForm.append(tgt);

	// Create options
	var options = $('<div></div>');
	var optionsLabel = $('<label>Options:</label>');	
	var optionsList = $('<ul></ul>');
	options.append(optionsLabel);
	options.append(optionsList);
	updatenodeForm.append(options);
		
	// Create update all software checkbox (only AIX)
	if (osHash['AIX']) {
		var updateAllOption = $('<li></li>');
    	var updateAllChkBox = $('<input type="checkbox" id="A" name="A"/>');
    	updateAllOption.append(updateAllChkBox);
    	optionsList.append(updateAllOption);
    	updateAllOption.append('Install or update all software contained in the source directory');
    	
    	// Create source directory input
    	var allSwScrDirectory = $('<li><label for="allSwSrcDirectory" style="vertical-align: middle">Source directory:</label><input type="text" id="allSwSrcDirectory" name="allSwSrcDirectory"/></li>');
    	// Browse server directory and files
    	var allSWSrcDirBrowse = createButton('Browse');
    	allSWSrcDirBrowse.serverBrowser({
    		onSelect : function(path) {
    			$('#allSwSrcDirectory').val(path);
    		},
    		onLoad : function() {
    			return $('#allSwSrcDirectory').val();
    		},
    		knownExt : [ 'exe', 'js', 'txt' ],
    		knownPaths : [ {
    			text : 'Install',
    			image : 'desktop.png',
    			path : '/install'
    		} ],
    		imageUrl : 'images/',
    		systemImageUrl : 'images/',
    		handlerUrl : 'lib/getpath.php',
    		title : 'Browse',
    		requestMethod : 'POST',
    		width : '500',
    		height : '300',
    		basePath : '/install' // Limit user to only install directory
    	});
    	allSwScrDirectory.append(allSWSrcDirBrowse);
    	allSwScrDirectory.hide();
    	optionsList.append(allSwScrDirectory);

    	// Show source directory when checked
    	updateAllChkBox.bind('click', function(event) {
    		if ($(this).is(':checked')) {
    			allSwScrDirectory.show();
    		} else {
    			allSwScrDirectory.hide();
    		}
    	});
	}
	
	// Create update software checkbox
	var updateOption = $('<li></li>');
	var updateChkBox = $('<input type="checkbox" id="S" name="S"/>');
	optionsList.append(updateOption);
	updateOption.append(updateChkBox);
	updateOption.append('Update existing software');
		
	// Create source directory input
	var scrDirectory = $('<li><label for="srcDirectory" style="vertical-align: middle">Source directory:</label><input type="text" id="srcDirectory" name="srcDirectory" title="You must give the source directory containing the updated software packages"/></li>');
	// Browse server directory and files
	var srcDirBrowse = createButton('Browse');
	srcDirBrowse.serverBrowser({
		onSelect : function(path) {
			$('#srcDirectory').val(path);
		},
		onLoad : function() {
			return $('#srcDirectory').val();
		},
		knownExt : [ 'exe', 'js', 'txt' ],
		knownPaths : [ {
			text : 'Install',
			image : 'desktop.png',
			path : '/install'
		} ],
		imageUrl : 'images/',
		systemImageUrl : 'images/',
		handlerUrl : 'lib/getpath.php',
		title : 'Browse',
		requestMethod : 'POST',
		width : '500',
		height : '300',
		basePath : '/install' // Limit user to only install directory
	});
	scrDirectory.append(srcDirBrowse);
	scrDirectory.hide();
	optionsList.append(scrDirectory);
	
	// Create other packages input
	var otherPkgs = $('<li><label for="otherpkgs" style="vertical-align: middle">otherpkgs:</label><input type="text" id="otherpkgs" name="otherpkgs"/></li>');
	otherPkgs.hide();
	optionsList.append(otherPkgs);
	
	// Create RPM flags input (only AIX)
	var aixRpmFlags = $('<li><label for="rpm_flags">rpm_flags:</label><input type="text" name="rpm_flags"/></li>');
	aixRpmFlags.hide();
	optionsList.append(aixRpmFlags);
	
	// Create installp flags input (only AIX)
	var aixInstallPFlags = $('<li><label for="installp_flags">installp_flags:</label><input type="text" name="installp_flags"/></li>');
	aixInstallPFlags.hide();
	optionsList.append(aixInstallPFlags);
	
	// Create emgr flags input (only AIX)
	var aixEmgrFlags = $('<li><label for="emgr_flags">emgr_flags:</label><input type="text" name="emgr_flags"/></li>');
	aixEmgrFlags.hide();
	optionsList.append(aixEmgrFlags);
	
	// Show flags when checked
	updateChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			scrDirectory.show();
			otherPkgs.show();
			if (osHash['AIX']) {
    			aixRpmFlags.show();
    			aixInstallPFlags.show();
    			aixEmgrFlags.show();
			}
		} else {
			scrDirectory.hide();
			otherPkgs.hide();
			if (osHash['AIX']) {
    			aixRpmFlags.hide();
    			aixInstallPFlags.hide();
    			aixEmgrFlags.hide();
			}
		}
	});
	
	// Create postscripts input
	var postOption = $('<li></li>');
	var postChkBox = $('<input type="checkbox" id="P" name="P"/>');
	optionsList.append(postOption);
	postOption.append(postChkBox);
	postOption.append('Run postscripts');
	var postscripts = $('<li><label for="postscripts" style="vertical-align: middle">Postscripts:</label><input type="text" id="postscripts" name="postscripts" title="You must give the postscript(s) to run"/></li>');
	postscripts.hide();
	optionsList.append(postscripts);
	
	// Show alternate source directory when checked
	postChkBox.bind('click', function(event) {
		if ($(this).is(':checked')) {
			postscripts.show();
		} else {
			postscripts.hide();
		}
	});
	optionsList.append('<li><input type="checkbox" id="F" name="F"/>Distribute and synchronize files</li>');
	optionsList.append('<li><input type="checkbox" id="k" name="k"/>Update the ssh keys and host keys for the service nodes and compute nodes</li>');
	
	// Create update OS checkbox
	if (!osHash['AIX']) {
		var osOption = $('<li></li>');
    	var osChkBox = $('<input type="checkbox" id="o" name="o"/>');
    	optionsList.append(osOption);
    	osOption.append(osChkBox);
    	osOption.append('Update the operating system');
    	
    	var os = $('<li></li>').hide();
    	var osLabel = $('<label for="os">Operating system:</label>');
    	var osInput = $('<input type="text" name="os" title="You must give the operating system to upgrade to, e.g. rhel5.5"/>');
    	osInput.one('focus', function(){
    		var tmp = $.cookie('osvers');
    		if (tmp) {
    			// Turn on auto complete
    			$(this).autocomplete(tmp.split(','));
    		}
    	});
    	os.append(osLabel);
    	os.append(osInput);
    	optionsList.append(os);
    	
    	// Show alternate source directory when checked
    	osChkBox.bind('click', function(event) {
    		if ($(this).is(':checked')) {
    			os.show();
    		} else {
    			os.hide();
    		}
    	});
	}
	
	// Generate tooltips
	updatenodeForm.find('div input[title]').tooltip({
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
	okBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		var ready = true;
		
		// Generate arguments
		var chkBoxes = $("#" + newTabId + " input[type='checkbox']:checked");
		var optionsStr = '';
		var option;
		for ( var i = 0; i < chkBoxes.length; i++) {
			option = chkBoxes.eq(i).attr('name');
			optionsStr += '-' + option;
			
			// If update all software is checked
			if (option == 'S') {
				var srcDir = $('#' + newTabId + ' input[name=allSwSrcDirectory]').val();
				if (srcDir) {
					optionsStr += ';-d ' + srcDir;
				}
			}

			// If update software is checked
			if (option == 'S') {
				// Get source directory
				var srcDirectory = $('#' + newTabId + ' input[name=srcDirectory]').val();
				if (srcDirectory) {
					optionsStr += ';-d;' + srcDirectory;
				}
				
				// Get otherpkgs
				var otherpkgs = $('#' + newTabId + ' input[name=otherpkgs]').val();
				if (otherpkgs) {
					optionsStr += ';otherpkgs=' + otherpkgs;
				}
				
				// Get rpm_flags
				var rpm_flags = $('#' + newTabId + ' input[name=rpm_flags]').val();
				if (rpm_flags) {
					optionsStr += ';rpm_flags=' + rpm_flags;
				}
				
				// Get installp_flags
				var installp_flags = $('#' + newTabId + ' input[name=installp_flags]').val();
				if (installp_flags) {
					optionsStr += ';installp_flags=' + installp_flags;
				}
				
				// Get emgr_flags
				var emgr_flags = $('#' + newTabId + ' input[name=emgr_flags]').val();
				if (emgr_flags) {
					optionsStr += ';emgr_flags=' + emgr_flags;
				}
			}
			
			// If postscripts is checked
			if (option == 'P') {
				// Get postscripts
				optionsStr += ';' + $('#' + newTabId + ' input[name=postscripts]').val();
			}
			
			// If operating system is checked
			if (option == 'o') {
				// Get the OS
				optionsStr += ';' + $('#' + newTabId + ' input[name=os]').val();
			}
			
			// Append ; to end of string
			if (i < (chkBoxes.length - 1)) {
				optionsStr += ';';
			}
		}
		
		// If no inputs are empty
		if (ready) {
			// Get nodes
			var tgts = $('#' + newTabId + ' input[name=target]').val();

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
					cmd : 'updatenode',
					tgt : tgts,
					args : optionsStr,
					msg : 'out=' + statBarId + ';cmd=updatenode;tgt=' + tgts
				},

				success : updateStatusBar
			});

			// Show status bar
			statusBar.show();
		} else {
			// Show warning message
			var warn = createWarnBar('You are missing some values');
			warn.prependTo($(this).parent().parent());
		}
	});
	updatenodeForm.append(okBtn);

	// Append to discover tab
	tab.add(newTabId, 'Update', updatenodeForm, true);

	// Select new tab
	tab.select(newTabId);
}
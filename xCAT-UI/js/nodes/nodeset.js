/**
 * Load nodeset page
 * 
 * @param trgtNodes
 *            Targets to run nodeset against
 * @return Nothing
 */
function loadNodesetPage(trgtNodes) {
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

	// Open new tab
	// Create nodeset form
	var nodesetForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'nodesetStatusBar' + inst;
	var statBar = createStatusBar(statBarId);
	statBar.hide();
	nodesetForm.append(statBar);

	// Create loader
	var loader = createLoader('nodesetLoader');
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Set the boot state for a node range');
	nodesetForm.append(infoBar);

	// Create target node or group
	var tgt = $('<div><label for="target">Target node or group:</label><input type="text" name="target" value="' + trgtNodes + '"/></div>');
	nodesetForm.append(tgt);

	// Create boot method drop down
	var method = $('<div></div>');
	var methodLabel = $('<label for="method">Boot method:</label>');
	var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
	methodSelect.append('<option value="boot">boot</option>');
	methodSelect.append('<option value="install">install</option>');
	methodSelect.append('<option value="iscsiboot">iscsiboot</option>');
	methodSelect.append('<option value="netboot">netboot</option>');
	methodSelect.append('<option value="statelite">statelite</option>');
	method.append(methodLabel);
	method.append(methodSelect);
	nodesetForm.append(method);

	// Create boot type drop down
	var type = $('<div></div>');
	var typeLabel = $('<label for="type">Boot type:</label>');
	var typeSelect = $('<select id="bootType" name="bootType"></select>');
	typeSelect.append('<option value="zvm">zvm</option>');
	typeSelect.append('<option value="install">pxe</option>');
	typeSelect.append('<option value="iscsiboot">yaboot</option>');
	type.append(typeLabel);
	type.append(typeSelect);
	nodesetForm.append(type);

	// Create operating system input
	var os = $('<div></div>');
	var osLabel = $('<label for="os">Operating system:</label>');
	var osInput = $('<input type="text" name="os"/>');
	osInput.one('focus', function(){
		var tmp = $.cookie('OSVers');
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete(tmp.split(','));
		}
	});
	os.append(osLabel);
	os.append(osInput);
	nodesetForm.append(os);

	// Create architecture input
	var arch = $('<div></div>');
	var archLabel = $('<label for="arch">Architecture:</label>');
	var archInput = $('<input type="text" name="arch"/>');
	archInput.one('focus', function(){
		var tmp = $.cookie('OSArchs');
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete(tmp.split(','));
		}
	});
	arch.append(archLabel);
	arch.append(archInput);
	nodesetForm.append(arch);

	// Create profiles input
	var profile = $('<div></div>');
	var profileLabel = $('<label for="profile">Profile:</label>');
	var profileInput = $('<input type="text" name="profile"/>');
	profileInput.one('focus', function(){
		tmp = $.cookie('Profiles');
		if (tmp) {
			// Turn on auto complete
			$(this).autocomplete(tmp.split(','));
		}
	});
	profile.append(profileLabel);
	profile.append(profileInput);
	nodesetForm.append(profile);

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
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

			// Disable Ok button
			$(this).unbind(event);
			$(this).css( {
				'background-color' : '#F2F2F2',
				'color' : '#424242'
			});

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
			alert('You are missing some values');
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
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
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
			$('#' + statBarId).append('<p>(Error) Failed to create node definition</p>');
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
			
			$('#' + statBarId).append('<p>Node definition created for ' + tgtNodesStr + '</p>');
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
			$('#' + statBarId).append('<p>(Error) Failed to update /etc/hosts</p>');
		} else {
			$('#' + statBarId).append('<p>/etc/hosts updated</p>');
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
		$('#' + statBarId).append(prg);	
		
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
		$('#' + statBarId).append(prg);	

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
		$('#' + statBarId).append(prg);	

		// Hide loader
		$('#' + statBarId).find('img').hide();
	}
}
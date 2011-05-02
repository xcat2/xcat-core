/**
 * Global variables
 */
var gangliaTableId = 'nodesDatatable';
var gangliaData;

/**
 * Load Ganglia monitoring tool
 * 
 * @return Nothing
 */
function loadGangliaMon() {
	// Get Ganglia tab
	var gangliaTab = $('#gangliamon');

	// Check whether Ganglia RPMs are installed on the xCAT MN
	$.ajax({
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q rrdtool ganglia-gmetad ganglia-gmond ganglia-web'
		},

		success : checkGangliaRPMs
	});

	// Create groups and nodes DIV
	var groups = $('<div id="groups"></div>');
	var nodes = $('<div id="nodes"></div>');
	gangliaTab.append(groups);
	gangliaTab.append(nodes);

	// Create info bar
	var info = createInfoBar('Select a group to view its nodes');
	nodes.append(info);

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

		success : loadGroups4Ganglia
	});

	return;
}

/**
 * Check whether Ganglia RPMs are installed
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function checkGangliaRPMs(data) {
	var gangliaTab = $('#gangliamon');

	// Get the list of Ganglia RPMs installed
	var status = data.rsp.split(/\n/);
	var gangliaRPMs = [ "rrdtool", "ganglia-gmetad", "ganglia-gmond", "ganglia-web" ];
	var warningMsg = 'Before continuing, please install the following packages: ';
	var missingRPMs = false;
	for ( var i in status) {
		if (status[i].indexOf("not installed") > -1) {
			warningMsg += gangliaRPMs[i] + ' ';
			missingRPMs = true;
		}
	}

	// Append Ganglia PDF
	if (missingRPMs) {
		warningMsg += ". Refer to <a href='http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf'>xCAT2-Monitoring.pdf</a> for more information.";

		var warningBar = createWarnBar(warningMsg);
		warningBar.css('margin-bottom', '10px');
		warningBar.prependTo(gangliaTab);
	} else {
		// Check if ganglia is running on the xCAT MN
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monls',
				tgt : '',
				args : 'gangliamon',
				msg : ''
			},

			/**
			 * Append warning message
			 * 
			 * @param data
			 *            Data returned from HTTP request
			 * @return Nothing
			 */
			success : function(data) {
				if (data.rsp[0].indexOf("not-monitored") > -1) {
					// Create link to start Ganglia
					var startLnk = $('<a href="#">Click here</a>');
					startLnk.css( {
						'color' : 'blue',
						'text-decoration' : 'none'
					});
					startLnk.click(function() {
						// Turn on Ganglia for all nodes
						monitorNode('', 'on');
					});
		
					// Create warning bar
					var warningBar = $('<div class="ui-state-error ui-corner-all"></div>');
					var msg = $('<p></p>');
					msg.append('<span class="ui-icon ui-icon-alert"></span>');
					msg.append('Please start Ganglia Monitoring on xCAT. ');
					msg.append(startLnk);
					msg.append(' to start Ganglia Monitoring.');
					warningBar.append(msg);
					warningBar.css('margin-bottom', '10px');
		
					// If there are any warning messages, append this warning after it
					var curWarnings = $('#gangliamon').find('.ui-state-error');
					var gangliaTab = $('#gangliamon');
					if (curWarnings.length) {
						curWarnings.after(warningBar);
					} else {
						warningBar.prependTo(gangliaTab);
					}
				}
			}
		});
	}
	return;
}

/**
 * Load groups
 * 
 * @param data
 *            Data returned from HTTP request
 * @return
 */
function loadGroups4Ganglia(data) {
	// Remove loader
	$('#groups').find('img').remove();

	var groups = data.rsp;
	setGroupsCookies(data);

	// Create a list of groups
	var ul = $('<ul></ul>');
	var item = $('<li id="root"><h3>Groups</h3></li>');
	ul.append(item);
	var subUL = $('<ul></ul>');
	item.append(subUL);

	// Create a link for each group
	for ( var i = groups.length; i--;) {
		var subItem = $('<li id="' + groups[i] + '"></li>');
		var link = $('<a>' + groups[i] + '</a>');
		subItem.append(link);
		subUL.append(subItem);
	}

	// Turn groups list into a tree
	$('#groups').append(ul);
	$('#groups').jstree( {
		core : {
			"initially_open" : [ "root" ]
		},
		themes : {
			"theme" : "default",
			"dots" : false, // No dots
			"icons" : false // No icons
		}
	});

	// Load nodes onclick
	$('#groups').bind('select_node.jstree', function(event, data) {
			// If there are subgroups, remove them
			data.rslt.obj.children('ul').remove();
			var thisGroup = jQuery.trim(data.rslt.obj.text());
			if (thisGroup) {
				// Clear nodes division
			$('#nodes').children().remove();

			// Create link to Ganglia
			var gangliaLnk = $('<a href="#">Click here</a>');
			gangliaLnk.css( {
				'color' : 'blue',
				'text-decoration' : 'none'
			});
			gangliaLnk.click(function() {
				// Open a new window for Ganglia
				window.open('../ganglia/');
			});

			// Create info bar
			var info = $('<div class="ui-state-highlight ui-corner-all"></div>');
			info.append('<span class="ui-icon ui-icon-info" style="display: inline-block; margin: 10px 5px;"></span>');
			var msg = $('<p style="display: inline-block; width: 95%;"></p>');
			msg.append('Below is a summary of nodes within the selected group. ');
			msg.append(gangliaLnk);
			msg.append(' to open the Ganglia page.');
			info.append(msg);
			info.css('margin-bottom', '10px');
			$('#nodes').append(info);

			// Create loader
			var loader = $('<center></center>').append(createLoader());
			$('#nodes').append(loader);

			// To improve performance, get all nodes within selected group
			// Get node definitions only for first 50 nodes
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'nodels',
					tgt : thisGroup,
					args : '',
					msg : thisGroup
				},

				/**
				 * Get node definitions
				 * 
				 * @param data
				 *            Data returned from HTTP request
				 * @return Nothing
				 */
				success : function(data) {
					var group = data.msg;
										
					// Get nodes definitions
					$.ajax( {
						url : 'lib/cmd.php',
						dataType : 'json',
						data : {
							cmd : 'nodestat',
							tgt : group,
							args : '',
							msg : group
						},

						success : loadGangliaSummary
					});
				}
			});
						
			// Get subgroups within selected group
			// only when this is the parent group and not a subgroup
			if (data.rslt.obj.attr('id').indexOf('Subgroup') < 0) {
    			$.ajax( {
    				url : 'lib/cmd.php',
    				dataType : 'json',
    				data : {
    					cmd : 'extnoderange',
    					tgt : thisGroup,
    					args : 'subgroups',
    					msg : thisGroup
    				},
    
    				success : loadSubgroups
    			});
			}
		} // End of if (thisGroup)
	});
}

/**
 * Load Ganglia summary page
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadGangliaSummary(data) {	
	// Data returned
	var rsp = data.rsp;
	// Group name
	var group = data.msg;
	// Node attributes hash
	var attrs = new Object();
	
	var node, status, args;
	for ( var i in rsp) {
		// Get key and value
		args = rsp[i].split(':', 2);
		node = jQuery.trim(args[0]);
		status = jQuery.trim(args[1]);
		
		// Create a hash table
		attrs[node] = new Object();
		attrs[node]['status'] = status;		
	}
	
	// Save node attributes hash
	gangliaData = attrs;
	
	// Get the status of Ganglia
	// Then create pie chart for node and Ganglia status
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'gangliastatus;' + group,
			msg : ''
		},

		success : loadGangliaStatus
	});
}

/**
 * Load the status of Ganglia for a given group
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadGangliaStatus(data) {
	// Remove loader
	$('#nodes').find('img').remove();
	
	// Get datatable
	var ganglia = data.rsp;
	var node, ping, monitored;

	// Count nodes that are pingable and not pingable
	// and nodes that are pingable and monitored by Ganglia
	var pingWGanglia = 0;
	var pingWOGanglia = 0;
	var noping = 0;
	for ( var i in ganglia) {
		// ganglia[0] = nodeName and ganglia[1] = state
		node = jQuery.trim(ganglia[i][0]);
		monitored = jQuery.trim(ganglia[i][1]);
		ping = gangliaData[node]['status'];
		
		// If the node is monitored, increment count
		if (ping == 'sshd' && monitored == 'on') {
			pingWGanglia++;
		} else if (ping == 'sshd' && monitored == 'off') {
			pingWOGanglia++;
		} else {
			noping++;
		}
	}
		
	// Create pie chart
	var summary = $('<div id="ganglia_sum"></div>');
	$('#nodes').append(summary);
	
	// Create pie details
	var details = $('<div id="ganglia_details"></div>');
	$('#nodes').append(details);
		
	var pie = [['Ping & monitored', pingWGanglia], ['Ping & not monitored', pingWOGanglia], ['Noping', noping]];
	var chart = $.jqplot('ganglia_sum', [ pie ], {
		seriesDefaults : {
			renderer : $.jqplot.PieRenderer
		},
		seriesColors : [
			'#3CB548', '#FE9A2E', '#848484' // Green, orange, grey
		],
		legend : {
			show : true
		},
		grid : {
			background : 'transparent',
			borderColor : 'white',
			borderWidth : '0px',
			shadow : false
		},
		show : true
	});
	
	// Change CSS styling for legend
	summary.find('table').css({
		'border-style': 'none'
	}).find('td').css({
		'border-style': 'none'
	});
	
	// Show details on mouse-over
	$('#ganglia_sum').bind('jqplotDataMouseOver', function(env, srIndex, ptIndex, data) {
		// Show for 8 seconds before sliding up
		$('#ganglia_details').children().remove();
		$('#ganglia_details').show();
		$('#ganglia_details').append($('<p>' + data[1] + ' node(s) ' + data[0] + '</p>'));
		$('#ganglia_details').delay(8000).slideUp();
	});
	
	// Open nodes page on-click
	$('#ganglia_sum').bind('jqplotDataClick', function(env, srIndex, ptIndex, data) {
		window.open('../xcat/index.php');
	});
	
	// Special note
	// To redraw pie chart: 
	//     - Use chart.series[0].data[i] to reference existing data
	//     - Use chart.redraw() to redraw chart
}
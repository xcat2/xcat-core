/**
 * Load update page
 * 
 * @return Nothing
 */
function loadUpdatePage() {
	var repositoryDiv = $('<div id="repository"></div>');
	var rpmDiv = $('<div id="rpm"></div>');
	var statusDiv = createStatusBar("update");
	statusDiv.hide();

	$('#updateTab').append(statusDiv);
	$('#updateTab').append('<br>');
	$('#updateTab').append(repositoryDiv);
	$('#updateTab').append(rpmDiv);

	var infoBar = createInfoBar('Select the RPM and repository, then press Update');
	repositoryDiv.append(infoBar);

	repositoryDiv.append("<fieldset><legend>Repository</legend></fieldset>");

	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'ostype'
		},

		success : showRepository
	});

	rpmDiv.append("<fieldset></fieldset>");

	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q xCAT-client perl-xCAT xCAT-server xCAT xCAT-rmc xCAT-UI'
		},

		success : showRpmInfo
	});
}

/**
 * Show the RPM Repository, it can use user's last choice and input
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function showRepository(data) {
	var DevelRepository = "";
	var StableRepository = "";
	var Show = "";

	// get the corresponding repository by OS Type
	if ("aix" == data.rsp) {
		DevelRepository = "http://xcat.sourceforge.net/aix/devel/xcat-core/";
		StableRepository = "http://xcat.sourceforge.net/aix/xcat-core/";
	} else {
		DevelRepository = "http://xcat.sourceforge.net/yum/devel/xcat-core/";
		StableRepository = "http://xcat.sourceforge.net/yum/xcat-core/";
	}

	var repoList = $('<ol></ol>');

	// display the Devel Repository, remember user's last selection
	Show = Show + "<li><input type='radio' ";
	if (1 == $.cookie('xcatrepository')) {
		Show = Show + "checked='true'";
	}

	Show = Show + "name='reporadio' value='" + DevelRepository + "'>";
	Show = Show + DevelRepository + "(<strong>Devel</strong>)</li>";

	repoList.append(Show);

	// display the Stable Repository, remember user's last selection
	Show = "<li><input type='radio' ";
	if (2 == $.cookie('xcatrepository')) {
		Show = Show + "checked='true'";
	}

	Show = Show + "name='reporadio' value='" + StableRepository + "'>";
	Show = Show + StableRepository + "(<strong>Stable</strong>)</li>";

	repoList.append(Show);

	// display the Input Repository, remember user's last selection
	if (($.cookie('xcatrepository')) && (1 != $.cookie('xcatrepository')) && (2 != $.cookie('xcatrepository'))) {
		Show = "<li><input type='radio' checked='true' name='reporadio' value=''>Other: ";
		Show += "<input style='width: 500px' id='repositoryaddr' value='" + $.cookie('xcatrepository') + "'</li>";
	} else {
		Show = "<li><input type='radio' name='reporadio' value=''>Other: ";
		Show += "<input style='width: 500px' id='repositoryaddr' value=''</li>";
	}

	repoList.append(Show);
	$('#repository fieldset').append(repoList);
}

/**
 * Show all xCAT RPMs
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function showRpmInfo(data) {
	var Rpms = null;
	var Show = "";
	var RpmNames = new Array("xCAT-client", "perl-xCAT", "xCAT-server", "xCAT", "xCAT-rmc", "xCAT-UI");
	var temp = 0;
	if (null == data.rsp) {
		$('#rpm fieldset').append("Get Rpm Info Error!");
		return;
	}

	Rpms = data.rsp.split(/\n/);
	// no rpm installed, return
	if (1 > Rpms.length) {
		$('#rpm fieldset').append("No Rpm installed!");
		return;
	}

	// clear the old data
	$('#rpm fieldset').children().remove();
	$('#rpm fieldset').append("<legend>xCAT Rpm Info</legend>");

	Show = "<table id=rpmtable >";
	Show += "<thead><tr>";
	Show += "<th><input type='checkbox' id='selectall' value='' onclick='updateSelectAll()'></th>";
	Show += "<th><b>Package Name</b></th><th><b>Version</b></th>";
	Show += "</tr></thead>";

	for (temp = 0; temp < Rpms.length; temp++) {
		// empty line continue
		if ("" == Rpms[temp]) {
			continue;
		}

		// the rpm is not installed, continue
		if (-1 != Rpms[temp].indexOf("not")) {
			continue;
		}

		// show the version in table
		Show += "<tr>";
		Show += "<td><input type='checkbox' value='" + RpmNames[temp] + "'></td>";
		Show += "<td>" + RpmNames[temp] + "</td><td>" + Rpms[temp].substr(RpmNames[temp].length + 1) + "</td>";
		Show += "</tr>";
	}
	Show += "</table>";
	Show += "<br\>";
	$('#rpm fieldset').append(Show);

	// add the update button
	var updateButton = createButton('Update');
	$('#rpm fieldset').append(updateButton);
	updateButton.bind('click', function() {
		updateRpm();
	});
}

/**
 * Select all checkboxes
 * 
 * @return Nothing
 */
function updateSelectAll() {
	var check_status = $('#selectall').attr('checked');
	$('input:checkbox').attr('checked', check_status);
}

/**
 * Update selected xCAT RPMs
 * 
 * @return Nothing
 */
function updateRpm() {
	// Remove any warning messages
	$('#updateTab').find('.ui-state-error').remove();

	var rpmPath = $('input[type=radio]:checked').val();
	var rpmPathType = "0";
	var rpms = "";
	var temp = "";

	if (undefined == rpmPath) {
		rpmPath = "";
	}

	// select other and we should use the value in the input
	if ("" == rpmPath) {
		// user input the repo, and we must stroe it in the cookie
		rpmPath = $('#repositoryaddr').val();
		rpmPathType = rpmPath;
	} else {
		if (-1 == rpmPath.toLowerCase().indexOf("devel")) {
			rpmPathType = "2";
		} else {
			rpmPathType = "1";
			;
		}
	}

	$("input[type=checkbox]:checked").each(function() {
		temp = $(this).val();
		if ("" == temp) {
			return true;
		}

		var pattern = new RegExp("^" + temp + ",|," + temp + ",");

		if (pattern.test(rpms)) {
			return true;
		}
		rpms = rpms + temp + ",";
	});

	if (0 < rpms.length) {
		rpms = rpms.slice(0, -1);
	}

	// Check RPM and repository
	var errMsg = '';
	if (!rpms) {
		errMsg = "Please select the rpm!<br>";
	}

	if (!rpmPath) {
		errMsg += "Please select or input the repository!";
	}

	if (!rpms || !rpmPath) {
		// Show warning message
		var warn = createWarnBar(errMsg);
		warn.prependTo($('#updateTab'));
		return;
	}

	// remember users' choice and input
	$.cookie('xcatrepository', rpmPathType, {
		path : '/xcat',
		expires : 10
	});

	$('#update').show();
	$('#update').empty();
	$('#update').append("<p>Updating <b>" + rpms + "</b> from <b>" + rpmPath + "</b></p>");
	$('#update').append("<img id='loadingpic' src='images/loader.gif'>");
	$('#rpm button').attr('disabled', 'true');

	// send the update command to server
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'update;' + rpms + ";" + rpmPath,
			msg : ''
		},

		success : ShowUpdateResult
	});
}

/**
 * Show the results of the RPM update
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function ShowUpdateResult(data) {
	var temp = 0;
	$('#loadingpic').remove();

	var resArray = data.rsp[0].split(/\n/);
	if (0 < resArray.length) {
		// Show last lines
		if (('' == resArray[resArray.length - 1]) && (resArray.length > 1)) {
			$('#update').append(resArray[resArray.length - 2]);
		} else {
			$('#update').append(resArray[resArray.length - 1]);
		}

		// Create link to show details
		$('#update').append('<br><a>Show details</a>');
		$('#update a').bind('click', function() {
			// Toggle details and change text
			$('#resDetail').toggle();
			if ($('#update a').text() == 'Show details') {
				$('#update a').text('Hide details');
			} else {
				$('#update a').text('Show details');
			}
		});

		var resDetail = $('<div id="resDetail"></div>');
		resDetail.hide();
		$('#update').append(resDetail);

		for (temp = 0; temp < resArray.length; temp++) {
			resDetail.append(resArray[temp] + "<br>");
		}
	}

	// update the rpm info
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q xCAT-client perl-xCAT xCAT-server xCAT xCAT-rmc xCAT-UI'
		},

		success : showRpmInfo
	});

	$('#rpm button').attr('disabled', '');
}
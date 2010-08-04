function loadXcatMon(){
	//find the xcat mon tab
	var xcatMonTab = $('#xcatmon');
	
	//add the stauts bar first. id = 'xcatMonStatus'
	var StatusBar = createStatusBar('xcatMonStatus');
	StatusBar.append(createLoader());
	xcatMonTab.append(StatusBar);
	
	//add the configure button.
	var configButton = createButton('Configure');
	configButton.click(function(){
		if ($('#xcatMonConfig').is(':hidden')){
			$('#xcatMonConfig').show();
		}
		else{
			$('#xcatMonConfig').hide();
		}
	});	
	xcatMonTab.append(configButton);
	
	//add the configure div, id = 'xcatMonConfig'
	xcatMonTab.append("<div id='xcatMonConfig'></div>");
	$('#xcatMonConfig').hide();	
	
	//add button start, stop, cancel to the monconfig div
	loadXcatMonConfigure();
	
	//add the content of the xcat mon, id = 'xcatMonShow'
	xcatMonTab.append("<div id='xcatMonShow'></div>");

	//show the content of the page.
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'monls',
			tgt : '',
			args : 'xcatmon',
			msg : ''
		},

		success : loadXcatMonWorkStatus
	});	
}

function loadXcatMonWorkStatus(data){
	var xcatWorkStatus = data.rsp[0];
	
	//the xcat mon did not run
	if (-1 != xcatWorkStatus.indexOf('not-monitored')){
		$('#xcatMonStatus').empty().append('The xCAT Monitor is not working. Please start it first.');
		return;
	}
	
	//the xcatmon is running, show the result
	loadXcatMonShow();
}

function loadXcatMonConfigure(){
	//get the xcat mon configure div
	var xcatMonConfigDiv = $('#xcatMonConfig');
	xcatMonConfigDiv.empty();
	
	//add start button
	var startButton = createButton('Start');
	xcatMonConfigDiv.append(startButton);
	startButton.click(function(){
		$('#xcatMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monstart',
				tgt : '',
				args : 'xcatmon',
				msg : ''
			},

			success : function(data){
				//update the status bar, update the xcatmon show
				$('#xcatMonStatus').empty().append(data.rsp[0]);
				loadXcatMonShow();
			}
		});
	});
	
	//add stop buttons
	var stopButton = createButton('Stop');
	xcatMonConfigDiv.append(stopButton);
	stopButton.click(function(){
		$('#xcatMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monstop',
				tgt : '',
				args : 'xcatmon',
				msg : ''
			},

			success : function(data){
				$('#xcatMonStatus').empty().append(data.rsp[0]);
				$('#xcatMonShow').empty();
			}
		});
	});
	
	//add cancel button
	var cancelButton = createButton('Cancel');
	xcatMonConfigDiv.append(cancelButton);
	cancelButton.click(function(){
		$('#xcatMonConfig').hide();
	});
}

function loadXcatMonShow(){
	//update the status bar into waiting
	$('#xcatMonStatus').empty().append(createLoader());
	
	//get the latest xcatmon information
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'nodestat',
			tgt : 'lpar',
			args : '',
			msg : ''
		},

		success : updateXcatMonShow
	});	
}

function updateXcatMonShow(data){
	var temp = 0;
	var nodeStatus = data.rsp;
	var show = "";
	var tempArray;
	//update the status bar
	$('#xcatMonStatus').empty().append("Get nodes' status finished.");
	
	$('#xcatMonShow').empty();
	$('#xcatMonShow').append("<fieldset><legend>Node Status</legend></fieldset>");
	
	//get the nodestat from return data
	//the data.rsp is an array, it look like this:
	//['node1:ssh', 'node2:noping', 'node3:ssh']
	for (temp = 0; temp < nodeStatus.length; temp++){
		tempArray = nodeStatus[temp].split(':');
		show += '<p>' + tempArray[0] + ':' + tempArray[1] + '</p>';
	}
	$('#xcatMonShow fieldset').append(show);
	
	var refreshButton = createButton('Refresh');
	$('#xcatMonShow fieldset').append(refreshButton);
	refreshButton.click(function(){
		loadXcatMonShow();
	});
}
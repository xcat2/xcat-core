function loadGangliaMon(){
	var gangMonTab = $('#gangliamon');
	var gangMonStatus = createStatusBar('gangMonStatus');
	gangMonTab.append(gangMonStatus);
	
	gangMonTab.append("<div id='gangMonConfig'></div>");
	$('#gangMonConfig').hide();
	addCfgButton();
	
	gangMonTab.append("<div id='gangLink'></div>");
	$('#gangLink').hide();
	addGangLink();
	
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q rrdtool ganglia-gmetad ganglia-gmond ganglia-web'
		},

		success : gangRpmCheck
	});
}

function addCfgButton(){
	var startButton = createButton('Start');
	$('#gangMonConfig').append(startButton);
	startButton.bind('click', function(){
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'gangliaStart',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
				$('#gangLink').show();
			}
		});
	});
	$('#gangMonConfig').append(startButton);
	
	var stopButton = createButton('Stop');
	$('#gangMonConfig').append(startButton);
	stopButton.bind('click', function(){
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rmcstop',
				tgt : '',
				args : 'gangliamon,-r',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
				$('#gangLink').hide();
			}
		});
	});
	$('#gangMonConfig').append(stopButton);
}

function addGangLink(){
	$('#gangLink').append('The Ganglia is running now. <br\>');
	$('#gangLink').append('please click <a href="">here</a> to open the Ganglia\'s main page');
	$('#gangLink a').click(function(){
		window.open('../ganglia/');
	});
}

function gangRpmCheck(data){
	var rpmStatus = data.rsp.split(/\n/);
	var stopFlag = false;
	var showString = "";
	var tempArray = ["rrdtool", "ganglia-gmetad", "ganglia-gmond", "ganglia-web"];
	
	for (var temp in rpmStatus){
		if(-1 != rpmStatus[temp].indexOf("not")){
			stopFlag = true;
			showString += "Please install <b>" + tempArray[temp] + "</b>.<br/>";
		}
	}
	
	if (stopFlag){
		showString += "<p>References: <a href='http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf'>xCAT2-Monitoring.pdf</a>.</p>";
		$('#gangMonStatus').empty().append(showString);
		return;
	}
	
	$('#gangMonConfig').show();
	
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'monls',
			tgt : '',
			args : 'gangliamon',
			msg : ''
		},
		
		success : function(data){
			if (-1 != data.rsp[0].indexOf("not-monitored")){
				$('#gangMonStatus').empty().append("Please start the Ganglia Monitoring first.");
				return;
			}
			
			$('#gangLink').show();
		}
	});
}
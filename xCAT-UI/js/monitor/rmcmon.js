function loadRmcMon(){
	//find the rmcmon tab
	var rmcMonTab = $('#rmcmon');
	
	//add the stauts bar first. id = 'rmcMonStatus'
	var rmcStatusBar = createStatusBar('rmcMonStatus');
	rmcStatusBar.append(createLoader());
	rmcMonTab.append(rmcStatusBar);
	
	//add the configure button.
	var configButton = createButton('Configure');
	configButton.hide();
	configButton.click(function(){
		if ($('#rmcMonConfig').is(':hidden')){
			$('#rmcMonConfig').show();
		}
		else{
			$('#rmcMonConfig').hide();
		}
	});		
	rmcMonTab.append(configButton);
	
	//add configure div
	rmcMonTab.append("<div id='rmcMonConfig'></div>");
	$('#rmcMonConfig').hide();
	
	//load the configure div's content
	loadRmcMonConfigure();
	
	//add the content of the rmcmon, id = 'rmcMonTab'
	rmcMonTab.append("<div id='rmcMonShow'></div>");
	
	//check the software work status by platform(linux and aix)
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'ostype'
		},

		success : rsctRpmCheck
	});
}

function loadRmcMonConfigure(){
	//get the configure div and clean its content.
	var rmcmonCfgDiv = $('#rmcMonConfig');
	rmcmonCfgDiv.empty();
	
	//add the start button
	var startButton = createButton('Start');
	rmcmonCfgDiv.append(startButton);
	startButton.click(function(){
		$('#rmcMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : 'rmcstart;lpar',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
			}
		});
	});
	
	//add the stop button
	var stopButton = createButton('Stop');
	rmcmonCfgDiv.append(stopButton);
	stopButton.click(function(){
		$('#rmcMonStatus').empty().append(createLoader());
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monstop',
				tgt : '',
				args : 'rmcmon',
				msg : ''
			},

			success : function(data){
				$('#rmcMonStatus').empty().append(data.rsp[0]);
			}
		});
	});
	
	//add the cancel button
	var cancelButton = createButton('Cancel');
	rmcmonCfgDiv.append(cancelButton);
	cancelButton.click(function(){
		$('#rmcMonConfig').hide();
	});
}
function rsctRpmCheck(data){
	//linux had to check the rscp first
	if ('aix' != data.rsp){
		$.ajax( {
			url : 'lib/systemcmd.php',
			dataType : 'json',
			data : {
				cmd : 'rpm -q rsct.core'
			},

			success : function(data){
				if (-1 != data.rsp.indexOf("not")){
					$('#rmcMonStatus').empty().append(
					'Please install the <a href="http://www14.software.ibm.com/webapp/set2/sas/f/rsct/rmc/download/home.html" target="install_window">RSCT</a> first.<br/>' +
					'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
				}
				else{
					xcatrmcRpmCheck();
				}
			}
		});
	}
	else{		
		xcatrmcRpmCheck();
	}
}

function xcatrmcRpmCheck(){
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q xCAT-rmc rrdtool'
		},

		success : function(data){
			var softInstallStatus = data.rsp.split(/\n/);
			var needHelp = false;
			$('#rmcMonStatus').empty();
			//check the xcat-rmc
			if(-1 != softInstallStatus[0].indexOf("not")){
				needHelp = true;
				$('#rmcMonStatus').append(
				'Please install the <a href="http://xcat.sourceforge.net/#download" target="install_window">xCAT-rmc</a> first.<br/>');
			}
			
			//check the rrdtool
			if(-1 != softInstallStatus[1].indexOf("not")){
				needHelp = true;
				$('#rmcMonStatus').append(
					'Please install the <a href="http://oss.oetiker.ch/rrdtool/download.en.html" target="install_window">RRD-tool</a> first.<br/>');
			}
			
			//add help info or load the rmc show
			if (needHelp){
				$('#rmcMonStatus').append(
				'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
			}
			else{
				rmcWorkingCheck();
			}
		}
	});
}

function rmcWorkingCheck(){
	$('#rmcMonStatus').empty().append("Checking RMC working status.");
	$('#rmcMonStatus').append(createLoader());
	$('#rmcmon button:first').show();
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'monls',
			tgt : '',
			args : 'rmcmon',
			msg : ''
		},

		success : function(data){
			if (-1 != data.rsp[0].indexOf("not-monitored")){
				$('#rmcMonStatus').empty().append("Please start the RMC Monitoring first.");
				return;
			}
			loadRmcMonShow();
		}
	});
}
function loadRmcMonShow(){
	$('#rmcMonStatus').empty().append('The RMC Monitor is under construction.');
	$('#rmcMonShow').empty().append('under construction.');
}
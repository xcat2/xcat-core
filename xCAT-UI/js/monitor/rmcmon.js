function loadRmcMon(){
	//find the rmcmon tab
	var rmcMonTab = $('#rmcmon');
	
	//add the stauts bar first. id = 'rmcMonStatus'
	var rmcStatusBar = createStatusBar('rmcMonStatus');
	rmcStatusBar.append(createLoader());
	rmcMonTab.append(rmcStatusBar);
	
	//add the configure button.
	var configButton = createButton('Configure');
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
	$('#rmcMonConfig').append('under construction.');
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
					$('#rmcMonStatus').empty().append('Please install the RSCT first.<br/> The software can be downloaded from ' +
					'<a href="http://www14.software.ibm.com/webapp/set2/sas/f/rsct/rmc/download/home.html" target="install_window">RSCT\'s RMC subsystem.</a><br/>' +
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
			cmd : 'rpm -q xCAT-rmc'
		},

		success : function(data){
			if(-1 != data.rsp.indexOf("not")){
				$('#rmcMonStatus').empty().append('Please install the xCAT-rmc first.<br/> The software can be downloaded from ' +
						'<a href="http://xcat.sourceforge.net/#download" target="install_window">xCAT Download Page.</a><br/>'+
						'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
			}
			else{
				loadRmcMonShow();
			}
		}
	});
}

function loadRmcMonShow(){
	$('#rmcMonStatus').empty().append('The RMC Monitor is under construction.');
	$('#rmcMonShow').empty().append('under construction.');
}
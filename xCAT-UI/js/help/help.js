function loadHelpPage(){
	// Create help tab
    var tab = new Tab();
    tab.init();
    $('#content').append(tab.object());
    
	// Add help content
    var helpForm = $('<div class="form"></div>');
    helpForm.append(
    	'<fieldset>' + 
    		'<legend>Quick Start</legend>' +
    		'<ol>' +
            	'<li><a href="configure.php" style="color: blue;">1. Discover hardware</a><br/>Discover all hardware in the cluster. Define them in the xCAT database. Initialize your cluster.</li>' +
            	'<li><a href="index.php" style="color: blue;">2. Verify defined nodes</a><br/>View nodes definition by groups in a table or graphical style.</li>' +
            	'<li><a href="configure.php" style="color: blue;">3. Install compute nodes</a><br/>Copy useful files from DVD onto harddisk. Create Linux images. Install compute nodes in stateful, stateless, and statelite style.</li>' +
            	'<li><a href="provision.php" style="color: blue;">4. Provision nodes</a><br/>Create stateful, stateless, or statelite virtual machines. Install an operating system on a physical machine.</li>' +
            	'<li><a href="monitor.php" style="color: blue;">5. Monitor Cluster</a><br/>Monitor your xCAT cluster using one or more third party monitoring software such as Ganglia, RMC, etc. </li>' +
            '</ol>' +
        '</fieldset>' +
    	'<fieldset>' +
    		'<legend>Advanced</legend>' + 
    		'<ol>' + 
    			'<li><a href="configure.php" style="color: blue;">a. Edit the xCAT database tables</a></li>' + 
    			'<li><a href="configure.php" style="color: blue;">b. Update the xCAT RPM on the Management Node</a></li>' + 
    		'</ol>' + 
    	'</fieldset>');
    tab.add('helpTab', 'Help', helpForm, false);
}
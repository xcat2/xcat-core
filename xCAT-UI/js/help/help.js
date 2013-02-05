/**
 * Load the help page
 */
function loadHelpPage(){
    // Create help tab
    var tab = new Tab();
    tab.init();
    $('#content').append(tab.object());
    
    var helpForm = $('<div class="form"></div>');
    helpForm.append(
        '<fieldset>' + 
            '<legend>Quick Start</legend>' +
            '<div style="display: inline-table; vertical-align: middle;"><img src="images/help/quick_start.png" style="width: 90%;"></img></div>' +
            '<ol style="display: inline-table; vertical-align: middle;">' +
                '<li><a href="configure.php" style="color: blue;">1. Discover hardware</a><br/>Discover all hardware in the cluster. Define them in the xCAT database.</li>' +
                '<li><a href="index.php" style="color: blue;">2. View defined nodes</a><br/>View node definitions by groups in a table or graphical view.</li>' +
                '<li><a href="provision.php" style="color: blue;">3. Manage operating system images</a><br/>View operating system images defined in xCAT. Copy operating system ISOs into xCAT. Create stateful, stateless, or statelite images.</li>' +
                '<li><a href="provision.php" style="color: blue;">4. Provision nodes</a><br/>Create stateful, stateless, or statelite virtual machines. Install an operating system onto bare metal machines.</li>' +
                '<li><a href="provision.php" style="color: blue;">5. Manage and provision storage and networks</a><br/>Create network devices. Define storage for systems.</li>' +
                '<li><a href="monitor.php" style="color: blue;">6. Monitor cluster</a><br/>Monitor the xCAT cluster using one or more third party software such as Ganglia, RMC, etc. </li>' +
            '</ol>' +
        '</fieldset>' +
        '<fieldset>' +
            '<legend>Settings</legend>' + 
            '<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>' +
            '<ol style="display: inline-table; vertical-align: middle;">' +
                '<li><a href="configure.php" style="color: blue;">a. Manage and control user access</a></li>' +
                '<li><a href="configure.php" style="color: blue;">b. Edit the xCAT database tables</a></li>' + 
                '<li><a href="configure.php" style="color: blue;">c. Update xCAT packages</a></li>' + 
            '</ol>' + 
        '</fieldset>');
    tab.add('helpTab', 'Help', helpForm, false);
}
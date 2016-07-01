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
                '<li><a href="index.php" style="color: blue;">1. View defined nodes</a><br/>View node definitions by groups in a table.</li>' +
                '<li><a href="provision.php" style="color: blue;">2. Manage operating system images</a><br/>View operating system images defined in xCAT. Copy operating system ISOs into xCAT.</li>' +
                '<li><a href="provision.php" style="color: blue;">3. Provision nodes</a><br/>Create virtual machines. Install an operating system onto virtual machines.</li>' +
                '<li><a href="provision.php" style="color: blue;">4. Manage and provision storage and networks</a><br/>Create network devices. Define storage for systems.</li>' +
            '</ol>' +
        '</fieldset>' +
        '<fieldset>' +
            '<legend>Settings</legend>' +
            '<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>' +
            '<ol style="display: inline-table; vertical-align: middle;">' +
                '<li><a href="configure.php" style="color: blue;">a. Manage and control user access</a></li>' +
                '<li><a href="configure.php" style="color: blue;">b. Edit the xCAT database tables</a></li>' +
            '</ol>' +
        '</fieldset>');
    tab.add('helpTab', 'Help', helpForm, false);
}
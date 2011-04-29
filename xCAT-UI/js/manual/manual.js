function loadManualPage(){
 // Create monitor tab
    var tab = new Tab();
    tab.init();
    $('#content').append(tab.object());
    //add the help content
    var helpForm = $('<div class="form"></div>');
    helpForm.append('<fieldset><legend>Quick Start</legend><ol>' +
             '<li><a href="configure.php">1. Discover hardwares</a><br/>Discover all hardwares in the cluster. Define them into xCAT database. Initialize your cluster fast and easily. It is in the Discover tab.</li>' +
             '<li><a href="index.php">2. Verify defined nodes</a><br/>See nodes definition by groups in table style and graphical layout style.</li>' +
             '<li><a href="#" onclick="showProvisionHelp()">3. Install compute nodes</a><br/>Copy useful files from DVD into harddisk. Create Linux image. Install compute nodesin stateful, stateless and statelite style. It\'s all here.</li>' +
             '<li><a href="monitor.php">4. Monitor Cluster</a><br/>Allows you to plug-in one or more third party monitoring software such as Ganglia, RMC etc. to monitor the xCAT cluster. </li></ol></fieldset>' +
             '<fieldset><legend>Advanced</legend><ol><li><a href="configure.php">a. Edit the xCAT database tables directly</a></li><li><a href="configure.php">b. Update the xCAT RPM on Management node automatically</a></li></ol></fieldset>');
    tab.add('monitorTab', 'Guide', helpForm, false);
}
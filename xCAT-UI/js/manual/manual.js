function loadManualPage(){
 // Create monitor tab
    var tab = new Tab();
    tab.init();
    $('#content').append(tab.object());
    //add the help content
    var helpForm = $('<div class="form"></div>');
    helpForm.append('<fieldset><legend>Quick Start</legend><ol>' +
             '<li><a href="configure.php">1. Discover hardware</a><br/>Discover all hardware in the cluster. Define them in the xCAT database. Initialize your cluster.</li>' +
             '<li><a href="index.php">2. Verify defined nodes</a><br/>View nodes definition by groups in a table or graphical style.</li>' +
             '<li><a href="#" onclick="showProvisionHelp()">3. Install compute nodes</a><br/>Copy useful files from DVD into harddisk. Create Linux image. Install compute nodes in stateful, stateless and statelite style.</li>' +
             '<li><a href="monitor.php">4. Monitor Cluster</a><br/>Monitor your xCAT cluster using one or more third party monitoring software such as Ganglia, RMC, etc. </li></ol></fieldset>' +
             '<fieldset><legend>Advanced</legend><ol><li><a href="configure.php">a. Edit the xCAT database tables</a></li><li><a href="configure.php">b. Update the xCAT RPM on the Management Node</a></li></ol></fieldset>');
    tab.add('monitorTab', 'Guide', helpForm, false);
}
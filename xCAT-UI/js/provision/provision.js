/**
 * Global variables
 */
var provisionTabs; // Provision tabs

/**
 * Set the provision tab
 * 
 * @param obj Tab object
 */
function setProvisionTab(obj) {
    provisionTabs = obj;
}

/**
 * Get the provision tab
 * 
 * @param Nothing
 * @return Tab object
 */
function getProvisionTab() {
    return provisionTabs;
}

/**
 * Load provision page
 */
function loadProvisionPage() {
    // If the page is loaded
    if ($('#content').children().length) {
        // Do not load again
        return;
    }

    // Get OS image names
    if (!$.cookie('imagenames')){
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'tabdump',
                tgt : '',
                args : 'osimage',
                msg : ''
            },

            success : setOSImageCookies
        });
    }

    // Get groups
    if (!$.cookie('groups')){
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'extnoderange',
                tgt : '/.*',
                args : 'subgroups',
                msg : ''
            },

            success : setGroupsCookies
        });
    }
    
    // Create info bar
    var infoBar = createInfoBar('Select a platform to provision or re-provision a node on, then click Ok.');
    
    // Create provision page
    var provPg = $('<div class="form"></div>');
    provPg.append(infoBar);

    // Create provision tab
    var tab = new Tab('provisionPageTabs');
    setProvisionTab(tab);
    tab.init();
    $('#content').append(tab.object());

    // Create radio buttons for platforms
    var hwList = $('<ol>Platforms available:</ol>');
    var esx = $('<li><input type="radio" name="hw" value="esx" checked/>ESX</li>');
    var kvm = $('<li><input type="radio" name="hw" value="kvm"/>KVM</li>');
    var zvm = $('<li><input type="radio" name="hw" value="zvm"/>z\/VM</li>');
    var ipmi = $('<li><input type="radio" name="hw" value="ipmi"/>iDataPlex</li>');
    var blade = $('<li><input type="radio" name="hw" value="blade"/>BladeCenter</li>');
    var hmc = $('<li><input type="radio" name="hw" value="hmc"/>System p</li>');
    
    hwList.append(esx);
    hwList.append(kvm);
    hwList.append(zvm);
    hwList.append(blade);
    hwList.append(ipmi);
    hwList.append(hmc);
    provPg.append(hwList);

    /**
     * Ok
     */
    var okBtn = createButton('Ok');
    okBtn.bind('click', function(event) {
        // Get hardware that was selected
        var hw = $(this).parent().find('input[name="hw"]:checked').val();
        
        var inst = 0;
        var newTabId = hw + 'ProvisionTab' + inst;
        while ($('#' + newTabId).length) {
            // If one already exists, generate another one
            inst = inst + 1;
            newTabId = hw + 'ProvisionTab' + inst;
        }
        
        // Create an instance of the plugin
        var title = '';
        var plugin;
        switch (hw) {
            case "kvm":
                plugin = new kvmPlugin();
                title = 'KVM';
                break;
            case "esx":
                plugin = new esxPlugin();
                title = 'ESX';
                break;
            case "blade":
                plugin = new bladePlugin();
                title = 'BladeCenter';
                break;
            case "hmc":
                plugin = new hmcPlugin();
                title = 'System p';
                break;
            case "ipmi":
                plugin = new ipmiPlugin();
                title = 'iDataPlex';
                break;
            case "zvm":
                plugin = new zvmPlugin();
                title = 'z/VM';
                break;
        }

        // Select tab
        tab.add(newTabId, title, '', true);
        tab.select(newTabId);
        plugin.loadProvisionPage(newTabId);
    });
    provPg.append(okBtn);
    
    // Create resources tab
    var resrcPg = $('<div class="form"></div>');

    // Create info bar
    var resrcInfoBar = createInfoBar('Select a platform to view its current resources.');
    resrcPg.append(resrcInfoBar);

    // Create radio buttons for platforms
    var rsrcHwList = $('<ol>Platforms available:</ol>');
    esx = $('<li><input type="radio" name="rsrcHw" value="esx" checked/>ESX</li>');
    kvm = $('<li><input type="radio" name="rsrcHw" value="kvm"/>KVM</li>');
    zvm = $('<li><input type="radio" name="rsrcHw" value="zvm"/>z\/VM</li>');
    ipmi = $('<li><input type="radio" name="rsrcHw" value="ipmi"/>iDataPlex</li>');
    blade = $('<li><input type="radio" name="rsrcHw" value="blade"/>BladeCenter</li>');
    hmc = $('<li><input type="radio" name="rsrcHw" value="hmc"/>System p</li>');
    
    rsrcHwList.append(esx);
    rsrcHwList.append(kvm);
    rsrcHwList.append(zvm);
    rsrcHwList.append(blade);
    rsrcHwList.append(ipmi);
    rsrcHwList.append(hmc);
    
    resrcPg.append(rsrcHwList);

    var okBtn = createButton('Ok');
    okBtn.bind('click', function(event) {
        // Get hardware that was selected
        var hw = $(this).parent().find('input[name="rsrcHw"]:checked').val();

        // Generate new tab ID
        var newTabId = hw + 'ResourceTab';
        if (!$('#' + newTabId).length) {
            // Create loader
            var loader = $('<center></center>').append(createLoader(hw + 'ResourceLoader'));

            // Create an instance of the plugin
            var plugin = null;
            var displayName = "";
            switch (hw) {
                case "kvm":
                    plugin = new kvmPlugin();
                    displayName = "KVM";
                    break;
                case "esx":
                    plugin = new esxPlugin();
                    displayName = "ESX";
                    break;
                case "blade":
                    plugin = new bladePlugin();
                    displayName = "BladeCenter";
                    break;
                case "hmc":
                    plugin = new hmcPlugin();
                    displayName = "System p";
                    break;
                case "ipmi":
                    plugin = new ipmiPlugin();
                    displayName = "iDataPlex";
                    break;
                case "zvm":
                    plugin = new zvmPlugin();
                    displayName = "z\/VM";
                    break;
            }
            
            // Add resource tab and load resources
            tab.add(newTabId, displayName, loader, true);
            plugin.loadResources();
        }

        // Select tab
        tab.select(newTabId);
    });
    
    resrcPg.append(okBtn);    

    // Add provision tab
    tab.add('provisionTab', 'Provision', provPg, false);
    // Add image tab
    tab.add('imagesTab', 'Images', '', false);
    // Add resource tab
    tab.add('resourceTab', 'Resources', resrcPg, false);
    
    // Load tabs onselect
    $('#provisionPageTabs').bind('tabsselect', function(event, ui){ 
        // Load image page 
        if (!$('#imagesTab').children().length && ui.index == 1) {
            $('#imagesTab').append($('<center></center>').append(createLoader('')));
            loadImagesPage();
        }
    });
    
    // Open the quick provision tab
    if (window.location.search) {
        tab.add('quickProvisionTab', 'Quick Provision', '', true);
        tab.select('quickProvisionTab');
        
        var provForm = $('<div class="form"></div>');
        $('#quickProvisionTab').append(provForm);
        appendProvisionSection('quick', provForm);
    }
}
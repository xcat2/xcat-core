// Javascript functions needed by the groups page

$(document).ready(function(){
    window.nodetabs = $("#nodetabs > ul").tabs(		{ cookie: { expires: 30, path: '/' },
    	show: function(e,ui) {
    		if (ui.tab.href.search('#attributes-tab$') > -1) { loadAttrTab($(ui.panel)); }
    		if (ui.tab.href.search('#rvitals-tab$') > -1) { loadVitalsTab($(ui.panel)); }
		    if (ui.tab.href.search('#rpower-tab$') > -1) {
			    loadRpowerTab($(ui.panel));
   		    }
            if (ui.tab.href.search('#ping-tab$') > -1) {
                loadPingTab($(ui.panel));
            }
            if (ui.tab.href.search('#copy-tab$') > -1) {
                loadCopyTab($(ui.panel));
            }
            if (ui.tab.href.search('#spcfg-tab$') > -1) {
                loadSPCfgTab($(ui.panel));
            }
    	}});		// ends the properties passed to tabs()
  });


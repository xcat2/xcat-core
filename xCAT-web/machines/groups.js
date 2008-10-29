// Javascript functions needed by the groups page

$(document).ready(function(){
    window.nodetabs = $("#nodetabs > ul").tabs(		{ cookie: { expires: 30, path: '/' },
    	show: function(e,ui) {
    		if (ui.tab.href.search('#attributes-tab$') > -1) { loadAttrTab($(ui.panel)); }
    		}
    	});		// ends the properties passed to tabs()
  });


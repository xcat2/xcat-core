

jQuery.fn.customInput = function(){//from http://www.filamentgroup.com/examples/customInput/customInput.jquery.js
	$(this).each(function(i){
		if($(this).is('[type=checkbox],[type=radio]')){
			var input = $(this);

			// get the associated label using the input's id
			var label = $('label[for='+input.attr('id')+']');

			//get type, for classname suffix
			var inputType = (input.is('[type=checkbox]')) ? 'checkbox' : 'radio';

			// wrap the input + label in a div
			$('<div class="custom-'+ inputType +'"></div>').insertBefore(input).append(input, label);

			// find all inputs in this set using the shared name attribute
			var allInputs = $('input[name='+input.attr('name')+']');

			// necessary for browsers that don't support the :hover pseudo class on labels
			label.hover(
				function(){
					$(this).addClass('hover');
					if(inputType == 'checkbox' && input.is(':checked')){
						$(this).addClass('checkedHover');
					}
				},
				function(){$(this).removeClass('hover checkedHover');}
			);

			//bind custom event, trigger it, bind click,focus,blur events
			input.bind('updateState', function(){
				if (input.is(':checked')) {
					if (input.is(':radio')) {
						allInputs.each(function(){
							$('label[for='+$(this).attr('id')+']').removeClass('checked');
						});
					};
					label.addClass('checked');
				}
				else {label.removeClass('checked checkedHover checkedFocus');}

			})
			.trigger('updateState')
			.click(function(){
				$(this).trigger('updateState');
			})
			.focus(function(){
				label.addClass('focus');
				if(inputType == 'checkbox' && input.is(':checked')){
					$(this).addClass('checkedFocus');
				}
			})
			.blur(function(){label.removeClass('focus checkedFocus');});
		}
	});
};

function monPluginSetStat()
{
    $('.fg-button:not(.ui-state-disabled)')
    .hover(
        function() {
            $(this).addClass('ui-state-hover');
        },
        function() {
            $(this).removeClass('ui-state-hover');
        }
    )
    .click(
        function() {
//            if($(this).hasClass("ui-state-active")) {
                var plugin=$('.pluginstat.ui-state-active').attr('id');
                var todo = $(this).html();
                //$("#settings").tabs('select',2);
                //for the noderange, we have to check the <div> with id "nrtree-input", and also the 'custom-nr' textarea
                var value = "";
                //we check the textarea firstly,
                value = $("#custom-nr").val();
                //then, if the textarea is empty, we have to get the selection from nrtree
                if(!value) {
                    var i=0;
                    var node_selected = nrtree.selected_arr;
                    for(; i< node_selected.length; i++) {
                        value += node_selected[i].attr('id');
                    }
                    //remove the "," at the front
                    value = value.substr(1);
                }
                //get the value for "node status monitoring"

                //$("#feedback").html(value); //used for debug
                if(value == "") {value="all";}
                $.post("monitor/setup.php",{name:plugin,action:todo,nm:$("#stat1 form fieldset input:checked").attr('value'),nr:value},function(data) {
                    if(data=='successful') {
                        //update the status of the selected plugin
                        //reload the tabs for enable/disable
                        var tmp = $("#"+plugin).children();
                        $.get("monitor/options.php",{name:plugin,opt:"status"},function(stat){
                            if(stat == "Disabled") {
                                $(tmp[1]).html(plugin+"<br>"+stat);
                                $(tmp[0].firstChild).removeClass("ui-icon-circle-check").addClass("ui-icon-circle-close");
                                $("#settings").tabs('url',3,'monitor/options.php?name='+plugin+'&opt=enable').tabs("load",3);
                            }else {
                                $(tmp[1]).html(plugin+"<br>"+stat);
                                $(tmp[0].firstChild).removeClass("ui-icon-circle-close").addClass("ui-icon-circle-check");
                                $("#settings").tabs('url',3,'monitor/options.php?name='+plugin+'&opt=disable').tabs("load",3);
                            }
                        })
                    }
                });
            }
//        }
    );
}

/*setMonsettingTab is used to initialize the configuration of monsetting in the monlist */
function setMonsettingTab()
{
    makeEditable('monsetting','.editme', '.Ximg', '.Xlink');
    $("#reset").click(function() {
        alert('You sure you want to discard changes?');
        $("#settings").tabs("load",1);  //reload the "config" tabs
        $("#settings .ui-tabs-panel #accordion").accordion('activate',1);//activate the "monsetting" accordion
    });
    $("#monsettingaddrow").click(function() {
        var line = $(".mContent #tabTable tbody tr").length + 1;
        var newrow = formRow(line, 6, line%2);
        $(".mContent #tabTable tbody").append($(newrow));
        makeEditable('monsetting', '.editme2', '.Ximg2', '.Xlink2');
    });
    $("#saveit").click(function() {
        var plugin=$('.pluginstat.ui-state-active').attr('id');
        $.get("monitor/options.php",{name:plugin, opt:"savetab"},function(data){
            $("#settings").tabs("load",1);  //reload the "config" tabs
            $("#settings .ui-tabs-panel #accordion").accordion('activate',1);//activate the "monsetting" accordion
        });
    });
}

function nodemonSetStat()
{
    //enable/disable buttons for setting of the Node monitoring status
    $("#nodemonset .fg-buttonset .fg-button").hover(function() {
        $(this).addClass("ui-state-hover");
    },function() {
        $(this).removeClass("ui-state-hover");
    }).click(function(){
        //TODO
    });
}
function appmonSetStat()
{
    //TODO
}

//create the associations for the condition & response
//which is be used in the PHP function displayCondResp() in rmc_event_define.php
function mkCondResp()
{
    //get the name of the selected condition
    //then, get the selected noderange
    //then, get the response in "checked" status
    //then, run the command "mkcondresp"
    var cond_val = $(':input[name=conditions][checked]').val();
    var value="";//the noderange selected from the osi tree
    var i=0;
    var node_selected = nrtree.selected_arr;
    for(; i< node_selected.length; i++) {
        value += node_selected[i].attr('id');
    }
    //remove the "," at the front
    value = value.substr(1);
    var resps_obj = $(':input[name=responses][checked]');
    if(cond_val && resps_obj && value) {
        $.each(resps_obj,function(i,n) {
            //i is the index
            //n is the content
            //TODO:add one new php file to handle "mkcondresp" command
            $.get("monitor/makecondresp.php", {cond: cond_val, resp: n.value, nr: value}, function(data) {
                    //nothing to do right now.
            });
        });
        $("#notify_me").html("<p>The associations are created!</p>");
        $("#notify_me").addClass("ui-state-highlight");
        $("#association table tbody").load("monitor/updateCondRespTable.php");
    }
}

//clearEventDisplay()
//is used to clear the selection in the page for configuring the condtion&response association
function clearEventDisplay()
{
    $(':input[name=conditions][checked]').attr('checked', false);
    $(':input[name=responses][checked]').attr('checked', false);
}

//function control_RMCAssoc()
//is used to update the association table in rmc_event_define.php
function control_RMCAssoc(cond, node, resp, action)
{
    //TODO:for define_rmc_event
    //control the RMC Association: startcondresp & stopcondresp;
    $.get("monitor/updateCondResp.php",
        {c: cond, n: node, r: resp, a: action},
        function(data) {
            $("#association table tbody").load("monitor/updateCondRespTable.php");
        }
    );
}

/*when one RMC Resource is selected, this function is called to display its attributes*/
function showRMCAttrib()
{
    var class_val = $('input[name=classGrp]:checked').val();
    if(class_val) {
        $.get("monitor/rmc_resource_attr.php", {name: class_val}, function(data) {
            $("#rmcSrcAttr").html(data);
        });
    }
}


// for the progress bar
myBar.loaded('monitor.js');
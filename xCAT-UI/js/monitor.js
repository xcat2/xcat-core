

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
				function(){ $(this).removeClass('hover checkedHover'); }
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
				else { label.removeClass('checked checkedHover checkedFocus'); }

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
			.blur(function(){ label.removeClass('focus checkedFocus'); });
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

// for the progress bar
myBar.loaded('monitor.js');
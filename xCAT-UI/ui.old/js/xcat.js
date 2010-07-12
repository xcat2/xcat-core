// Javascript functions

function injs() {	
		jQuery('ul.sf-menu').superfish();

		// got this next part from:
		// http://nettuts.com/javascript-ajax/how-to-load-in-and-animate-content-with-jquery/	
		// Check for hash value in URL

 		var hash = window.location.hash.substr(1);
		var fullLoc = hash;
		//alert(hash);
		// check to see if there is a query of it.
		if(hash.indexOf("?") !=-1){
			hash = 	hash.slice(0,hash.indexOf("?"));
		//	alert(hash);
		}
		var href = $('#sf-menu li a').each(function(){
			var href = $(this).attr('href');
			// alert(href + " = " + hash + "?");
			if(hash==href){
				var toLoad = fullLoc;
				$('#main').load(toLoad)
				// change the document title
				var subM = href.slice(0,href.indexOf(".php"));
				document.title = "xCAT: " + subM;
    			} 
		});

		// if no page is specified load the default main page.
		if(hash == false ){
			$('#main').load('main.php');
			document.title = "xCAT Control Center";
		}


    $('#sf-menu li a').click(function(){
			var toLoad = $(this).attr('href');
			$('#main').hide('fast',loadContent);
			$('#load').remove();
			$('#wrapper').append('<span id="load">LOADING...</span>');
			$('#load').fadeIn('normal');
			// update the location
			// window.location.hash = $(this).attr('href').substr(0,$(this).attr('href').length-5);
			window.location.hash = $(this).attr('href');
			// update the title
			document.title = "xCAT: " + $(this).attr('href').slice(0,$(this).attr('href').indexOf(".php"));

			function loadContent() {
				$('#main').load(toLoad,'',showNewContent())
			}

			function showNewContent() {
    		$('#main').show('normal',hideLoader());
			}
			function hideLoader() {
				$('#load').fadeOut('normal');
			}
			return false;
		});


		// code for processing form
		var options = {
			target: '#main',
			url: 'command.php'
		}
		$('#cmdForm').hover(function(){
			$(this).css("background", "url(img/cmd-active.png) no-repeat")
			},function(){
			$(this).css("background", "url(img/cmd.png) no-repeat")
		});
		$('#cmdForm').ajaxForm(options);
		$('#cmd').focus(function() {
			this.value	= "";
		});
}


function loadConfigTab(tab) {
	// if they don't add a table definition, just go to the
	// main page.
	if(tab === undefined){
		document.title = "xCAT: config";
    		$('#main').load('config.php');
		window.location.hash = "config.php";
	}else{
		// update the title
		document.title = "xCAT: config " + tab;
		// update the URL
		window.location.hash = "config.php?t=" + tab;
	
		// load the page
		$('#main').load('config.php?t=' + tab);
	}
}


function controlCmd(cmd, nr){
	//var nrt = $("#nrcmdnoderange").html();
	// strip off Noderange:
	//var nr = nrt.split(" ");
	//nr = nr[1];
	$("#nrcmdnodegrange").text("Noderange: " + nr);
	$("#nrcmdcmd").text("Action: " + cmd);
	// update window command
	window.location.hash = "control.php?nr="+ nr + "&cmd=" + cmd;
	$('#rangedisplay').empty().html('<img src="img/throbber.gif">');	
	$('#rangedisplay').load('rangeDisplay.php?t=control&nr='+nr+'&cmd='+cmd);
}

function loadMainPage(page){
	// blank the page out
	$('#main').empty().html('<img src="img/throbber.gif">');	

	// change the title to the new one.
	var subM = page.slice(0,page.indexOf(".php"));
	document.title = "xCAT: " + subM;


	// load the page
	$('#main').load(page);

	// change the URL
	window.location.hash = page;
}



// call this to update the table with unique log entries.  
// we should probably be more robust cause we may miss some entries
// that happen at the same time.
function tableUpdater(count,oldEntry){

	// The first time this is called, oldEntry is nothing.
	if(oldEntry == ''){
		// this is the base date.
		oldEntry = "<tr>" + $("table tbody tr").html() + "</tr>";
	}

	$.get( "logentry.php?l="+count, function(html) {
			// get the existing entry and see if it matches:
			// we have to format it a little bit to make it match:
			var newEntry = html;
			if(oldEntry != newEntry) {
				// The next test we have to do is be sure that they 
				// newEntry is newer than old entry, just cause we see
				// bugs here when its going really fast
				if(badDates(oldEntry, newEntry)){
					// we're done cause the dates were bad.  Just stop here.
					t=setTimeout("tableUpdater(0,'')",5000);
					return;
				}
				// append this output to table body
				$("table tbody").append(html);
				// trigger the update
				$("table").trigger("update");
				// sort on first and second column with newest 
				// entry first 0 - column 0, 1- descending order
				var sorting = [ [0,1], [1,1]];
				$("table").trigger("sorton",[sorting]);

				// see if there were any more 
				tableUpdater(count + 1,oldEntry);
			}else{
				// The enties mached so now we're done looping.
				// we'll wait for 5 seconds and see if something new comes.
				//alert('dates are the same');
				t=setTimeout("tableUpdater(0,'')",5000);
			}
		});
}

// make sure that old entry is actually older than new entry
function badDates(oldEntry,newEntry){
	var rc = 1;
	// brute force regular expressions!!!
	var oldDay = oldEntry.replace(/<tr>\n<td>(\w+\s+\d+).*\n.*\n.*\n.*\n.*\n.*/gi,"$1");
	var newDay = newEntry.replace(/<tr>\n<td>(\w+\s+\d+).*\n.*\n.*\n.*\n.*\n.*/gi,"$1");
	var oldTime = oldEntry.replace(/<tr>\n<td>.*\n<td>(\d+:\d+:\d+).*\n.*\n.*\n.*\n.*/gi,"$1");
	var newTime = newEntry.replace(/<tr>\n<td>.*\n<td>(\d+:\d+:\d+).*\n.*\n.*\n.*\n.*/gi,"$1");
	//alert(newDay + '\n' + newTime);
	//alert(oldDay + '\n' + oldTime);
	// assume these happened in the same year...
	var d = new Date();
	var year = d.getFullYear();
	//alert('old date: ' + oldDay + ", " + year + " " + oldTime);
	var oDate = new Date(oldDay + ", " + year + " " + oldTime);
	var nDate = new Date(newDay + ", " + year + " " + newTime);
	//alert(oDate + nDate);	
	if(oDate.getTime() < nDate.getTime()){
		rc = 0;
	}
	return rc;
}

// These functions are the wizard for installing an OS:
// the screen has two divs: part1 and part2.
// as we walk through the  menues we start updateing.
// First we grab the OS:

// function for changing OS version type
function changeOS(){
	var os = $('#os').val();
	$("#nrcmdos").text("Operating System: " + os);
	if(os != ''){
		$("#part2").fadeIn(2000);	
	}else{
		// if you select null, then go back to the start
		$("#part2").css({'display' : 'none'});
	}
}


// next we grab the architecture.

function changeArch(){
	var arch = $("#arch").val();
	$("#nrcmdarch").text("Architecture: " + arch);
	// make sure its not an empty string
	if(arch != ''){
		var os = $("#nrcmdos").text();
		// have to get the OS, its :<space> then the value
		// that's why I add 2
		os = os.slice(os.indexOf(':')+2);
		var uri = '/install/' + os + '/' + arch + '/';
		$('#part1').empty().html('checking if media is present for ' + uri + '...');
		$('#part2').empty().html('<img src="img/throbber.gif">');	
		$('#part2').load(uri,"",
			function(responseText,textStatus,XMLHttpRequest) {

				if(textStatus == 'error'){
					$('#part2').empty();
					$('#part1').html("Looks like you need to copy the media first.  Please run copycds for " + os  + '-' + arch + '<br>Click on a noderange to start over');
				}else {
					$('#part1').empty();
					$('#part2').empty();
					$("#part3").fadeIn(2000);	
				}
			}
		);
	}
}


function changeMeth(){
	var meth = $('#method').val();
	if(meth != ''){
		$("#nrcmdmethod").text("Install Method: " + meth);
		$("#part3").empty();
		// get the OS:
		var os = $("#nrcmdos").text();
		os = os.slice(os.indexOf(':')+2);
		// get the Arch:
		var arch = $("#nrcmdarch").text();
		arch = arch.slice(arch.indexOf(':')+2);
		// get the noderange:
		var nr = $("#nrcmdnoderange").text();
		nr = nr.slice(nr.indexOf(':')+2);
		$("#part1").load('lib/profiles.php?nr='+nr+'&m='+meth+'&o='+os+'&a='+arch);
	}	
}

function changeProf(){
	var prof = $('#prof').val();
	if(prof != ''){
		$("#nrcmdprofile").text("Profile: " + prof);
		// get the OS:
		var os = $("#nrcmdos").text();
		os = os.slice(os.indexOf(':')+2);
		// get the Arch:
		var arch = $("#nrcmdarch").text();
		arch = arch.slice(arch.indexOf(':')+2);
		// get the noderange:
		var nr = $("#nrcmdnoderange").text();
		nr = nr.slice(nr.indexOf(':')+2);
		// get the method:
		var meth = $("#nrcmdmethod").text();
		meth = meth.slice(meth.indexOf(':')+2);

		// ask if this is really what they want to do.
		$("#part1").empty().html("Ok, xCAT is ready to provision the noderange <b>"+nr+"</b> with <b>"+os+"-"+arch+"-"+prof+"</b>  These nodes will be provisioned via the "+meth+" method.<br><br>Are you sure you want to do this?<br><br>")  
		$("#part2").empty().html("<a class='button' id='doit'><span>Yes, Do it!</span></a>");

		$("#doit").click(function(){
				var args = "nodetype.os="+os+" nodetype.arch="+arch+" nodetype.profile="+prof;
				$("#part1").empty().html("running: <i>nodech "+nr+ " "+args+"</i>");
				// put the waiting image while we run the command:
				$('#part2').empty().html('<img src="img/throbber.gif">');	
				// change the args so that we don't ask for any spaces:
				// we have to do this to encode it to the URL
				// yes, this does suck and no, I don't think
				// this function could be any more confusing.
				args = args.replace(/ /g, '+');
				$('#part2').load('command.php?nr='+nr+'&cmd=nodech&args='+args,'',
				function(responseText,textStatus,XMLHttpRequest) {
					if(textStatus != 'error'){
						$('#part2').html('Success.');
						$('#part3').html('running: <i>nodeset '+nr+' '+meth+'</i>');	
						$('#part4').html('<img src="img/throbber.gif">');	
						$('#part4').fadeIn('normal');	
						$('#part4').load('command.php?nr='+nr+'&cmd=nodeset&args='+meth,
							function(responseText,textStatus,XMLHttpRequest) {
								if(textStatus != 'error'){
									$('#part4').html('Success.'+responseText);
									$('#part5').html('running: <i>rpower '+nr+' boot</i>');
									$('#part5').fadeIn('normal');	
									$('#part6').html('<img src="img/throbber.gif">');	
									$('#part6').fadeIn('normal');	
									$('#part6').load('command.php?nr='+nr+'&cmd=rpower&args=boot',
										function(responseText,textStatus,XMLHttpRequest) {
											if(textStatus != 'error'){
												$('#part6').html('Nodes have rebooted and should be installing...'+responseText);
											}
										}
									);
								}
							}
						);
					}else{
						$('#part2').html('There was a problem...');
					}
				}
				);
			}
		);
	} // so yeah, all these }'s and )'s really suck.  I hope you never have to
		// debug this.  If you do, please make this code easier to read.
}

//added for display the tree
// TODO: there're still issues here.
function init_ositree(){
    //display all the nodes with OSI type
    nrtree = new tree_component();  //-tree begin
    nrtree.init($("#ositree"),{
        rules: {multiple: "Ctrl"},
        ui: {animation: 250},
        data : {
            type: "json",
            async: "true",
            url: "monitor/osi_source.php"
        }
    });
}

//function updatermcnr()
//{
//    myselection = nrtree.selected_arr;
//
//    for (node in myselection) {
//        $("#rmc_monshow").html($("#rmc_monshow").html()+node);
//    }
//
//}

//update the osi tree 
function init_rmc_ositree() {
    nrtree = new tree_component();  //-tree begin
    nrtree.init($("#rmc_tree"),{
        rules: {multiple: "Ctrl"},
        ui: {animation: 250},
        callback: {
            onchange: function(n) {
                $("#monshow_tip_1").hide();
                if(n.id) {
                    //if($(n).parent().parent().attr("id") == ",lpar") {
                    //parse the id, then display the "monshow" data for selected noderange
                    $.get("monitor/rmc_monshow_attr_source.php", {id: n.id}, function(data) {
                        //display the "monshow" result
                        $("#monshow_opt").html(data);
                    });
                    //}
                }
            }
        },
        //http://jstree.com/reference/_examples/3_callbacks.html
        //onchange is used to
        data : {
            type: "json",
            async: "true",
            url: "monitor/rmc_source.php"
        }
    });
}


function goto_next()
//TODO: change the function name! it's too silly now!
{
    var str = location.href;
    //TODO:one bug is here.
    var plugin=str.slice(str.indexOf("name")+5);//get the argument from "?name=xxxxx"
    if(plugin == "rmcmon") {
        loadMainPage("monitor/rmc_event_define.php");
    }else {
        //TODO
        //for the others, there's no web page to define evnets/performance now'
        loadMainPage("monitor/monstart.php?name="+plugin);
    }
}

function show_monshow_data(type,range)
{
    //type = "text" or "graph"
    //range = "cluster", "summary" and nodename
    //used in the web page "rmc_monshow.php"
    if($(":input[@checked]").size() != 0) {
        $("#monshow_data").empty();
        $("#monshow_opt").hide("slow");
        $("#back_btn").show("slow");
        $(":input[@checked]").each(function(i) {
            //generate text/graphics for all the attributes in "checked" status
            $.get("monitor/rmc_monshow_data_source.php", {mode: type, value: $(this).attr("value"), nr: range}, function(data) {
                $("#monshow_data").append(data);
            });
        });
    }else {
        $("#monshow_data").html("<p><b>Please select one or more attributes from the table</b></p>");
    }
}

function init_rmc_monshow_back_btn() {
    $("#back_btn").hide();
}

function rmc_monshow_back_to_opts() {
    //clear the <div id='monshow_data'>
    //and, display <div id='monshow_opts'>
    $("#monshow_data").empty();
    $("#back_btn").hide("slow");
    $("#monshow_opt").show("slow");
}

function handle_tips() {
    ///add dynamic effects for <div class="tips">
    $(".tips > .tips_content").hide();
    $(".tips > .tips_head").click(function() {
        if($(".tips > .tips_content").css("display") == "none") {
            $(".tips > .tips_head").html("<b>Tips:</b>(Click me to remove tips)");
            $(".tips > .tips_content").show("slow");
        }else {
            $(".tips > .tips_head").html("<b>Tips:</b>(Click me to display tips)");
            $(".tips > .tips_content").hide("slow");
        }
    });
}

function rmc_monshow_draw_by_flot(div, value)
{
    //collecting data from "monshow" command,
    //then, draw by the jQuery-plugin: flot
    //http://groups.google.com/group/flot-graphs/browse_thread/thread/93358c68d44412a4?pli=1
    //update the graph by every  minutes
    var division = document.getElementById(div);
    window.setInterval(function() {
        if($("#monshow_data") && $("#monshow_data").html() != "") {
            $.getJSON("monitor/flot_get_data.php", {attr: value}, function(data) {
                $.plot($(division),data, options);
            });
        }
    }
    , 60*1000);
    var options = {
        xaxis: {
            mode: 'time'
        },
        lines: {show: true, fill: true}
    };
 
    $.getJSON("monitor/flot_get_data.php", {attr: value}, function(data) {
        $.plot($(division),data, options);
    });
}

/*
 * loadLLCfgEditor()
 * nav the webpage to LoadLeveler editor if it exists
 */
function loadLLCfgEditor()
{
    window.document.location="../ll/llconfig_editor.pl";
}

/* 
 * loadNodeStatus()
 * will show the power status of all nodes in the cluster
 * with the help of "rpower all stat"
 * It's used in PHP function showNodeStat().
 */
function loadNodeStatus()
{
    $.get("rpowerstat.php", {type: "table"}, function(data) {
        $("#p_stat_table").html("<div id=stat_table></div>");
        $("#stat_table").html(data);
        $("#stat_table").dataTable({"bJQueryUI": true, "iDisplayLength": 50});
        $("#p_stat_table").show();
    });
}

function fun_js_select_all()
{
    var check_status = $('#selectall').attr('checked');
    $('input:checkbox').attr('checked', check_status);
}

function fun_js_update()
{
    var rpm_path = $('input[type=radio]:checked').val();
    var rpms = "";
    var temp = "";

    //select other and we should use the value in the input
    if ("" == rpm_path)
    {
        //user input the repo, and we must stroe it in the cookie
        rpm_path = $('#repositoryaddr').val() + "&remember=3";
    }
    else
    {
        if(-1 == rpm_path.toLowerCase().indexOf("devel"))
        {
            rpm_path = rpm_path + "&remember=1";
        }
        else
        {
            rpm_path = rpm_path + "&remember=2";
        }
    }

    $("input[type=checkbox]:checked").each(function(){
        temp = $(this).val();
        if("" == temp)
        {
            //continue;
            return true;
        }
        var pattern = new RegExp("^" + temp + ",|," + temp + ",");;
        if (pattern.test(rpms))
        {
            return true;
        }
        rpms = rpms + temp + ",";
    });

    if(0 < rpms.length)
    {
        rpms = rpms.slice(0, -1);
    }

    $('#updateProcess').empty().html('<img src="img/throbber.gif">');
    $('#updateProcess').load("updateprocess.php?repo=" + rpm_path + "&rpmname=" + rpms);
}

function fun_js_lsdef_edit()
{
    $('.attrvalue').editable(function(value, settings){return value;},
        {
        indicator : "updating...",
        type : 'text',
        tooltip     : 'Click to edit...',
        placeholder : '',
        onblur      : 'submit'
        }
     );

    $('.selected').editable(function(value, settings){
                            $(this).next(".attrvalue").attr("id", "lsdef_" + value);
                            },
                  {
                  loadurl : 'lsdefList.php',
                  indicator : "updating...",
                  type : 'select',
                  tooltip        : 'Click to select...',
                  placeholder    : '',
                  onblur     : 'submit'
                  });
}
// load progress bar
myBar.loaded('xcat.js');

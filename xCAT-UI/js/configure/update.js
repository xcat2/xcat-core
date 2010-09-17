/**
 * Load update page
 *
 * @return Nothing
 */
 function loadUpdatePage() {
	 
    var repositoryDiv = $('<div id="repository"></div>');
    var rpmDiv = $('<div id="rpm"></div>');
    var statusDiv = createStatusBar("update");
    statusDiv.hide();
    
    $('#updateTab').append(statusDiv);
	$('#updateTab').append('<br>');
    $('#updateTab').append(repositoryDiv);
    $('#updateTab').append(rpmDiv);
    
    
    var infoBar = createInfoBar('Select the Rpm and Repository, then press Update');
    repositoryDiv.append(infoBar);
    

    repositoryDiv.append("<fieldset><legend>Repository</legend></fieldset>");

    $.ajax( {
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'ostype'
        },

        success : showRepository
    });

    rpmDiv.append("<fieldset></fieldset>");

    $.ajax({
        url: 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpm -q xCAT-client perl-xCAT xCAT-server xCAT xCAT-rmc xCAT-UI'
        },

        success : showRpmInfo
    });
 }

/**
 * Show the Rpm Repository, it can use user's last choice and input
 *
 * @return Nothing
 */
function showRepository(data) {
    var DevelRepository = "";
    var StableRepository = "";
    var Show = "";

    //get the corresponding repository by OS Type
    if ("aix" == data.rsp)
    {
        DevelRepository = "http://xcat.sourceforge.net/aix/devel/xcat-core/";
        StableRepository = "http://xcat.sourceforge.net/aix/xcat-core/";
    }
    else
    {
        DevelRepository = "http://xcat.sourceforge.net/yum/devel/xcat-core/";
        StableRepository = "http://xcat.sourceforge.net/yum/xcat-core/";
    }

    //dispaly the Devel Repository, remember user's last selection
    Show = Show + "<input type='radio' ";
    if(1 == $.cookie('xcatrepository'))
    {
        Show = Show + "checked='true'";
    }

    Show = Show + "name='reporadio' value='" + DevelRepository + "'>";
    Show = Show + DevelRepository + "(<strong>Devel</strong>)<br/>";

    $('#repository fieldset').append(Show);

    //dispaly the Stable Repository, remember user's last selection
    Show = "<input type='radio' ";
    if(2 == $.cookie('xcatrepository'))
    {
        Show = Show + "checked='true'";
    }

    Show = Show + "name='reporadio' value='" + StableRepository + "'>";
    Show = Show + StableRepository + "(<strong>Stable</strong>)<br/>";

    $('#repository fieldset').append(Show);

    //dispaly the Input Repository, remember user's last selection
    if (($.cookie('xcatrepository'))
        && (1 != $.cookie('xcatrepository'))
        && (2 != $.cookie('xcatrepository')))
    {
        Show = "<input type='radio' checked='true' name='reporadio' value=''>Other:";
        Show += "<input style='width: 500px' id='repositoryaddr' value='" + $.cookie('xcatrepository') + "'<br/>";
    }
    else
    {
        Show = "<input type='radio' name='reporadio' value=''>Other:";
        Show += "<input style='width: 500px' id='repositoryaddr' value=''<br/>";
    }

    $('#repository fieldset').append(Show);
}

function showRpmInfo(data)
{
    var Rpms = null;
    var Show = "";
    var RpmNames = new Array("xCAT-client","perl-xCAT","xCAT-server","xCAT","xCAT-rmc","xCAT-UI");
    var temp = 0;
    if(null == data.rsp)
    {
        $('#rpm fieldset').append("Get Rpm Info Error!");
        return;
    }

    Rpms = data.rsp.split(/\n/);
    //no rpm installed, return
    if (1 > Rpms.length)
    {
        $('#rpm fieldset').append("No Rpm installed!");
        return;
    }

    //clear the old data
    $('#rpm fieldset').children().remove();
    $('#rpm fieldset').append("<legend>xCAT Rpm Info</legend>");
    
    Show = "<table id=rpmtable >";
    Show += "<tr>";
    Show += "<td><input type='checkbox' id='selectall' value='' onclick='updateSelectAll()'></td>";
    Show += "<td><b>Package Name</b></td><td><b>Version</b></td>";
    Show += "</tr>";

    for (temp = 0; temp < Rpms.length; temp++)
    {
        //empty line continue
        if ("" == Rpms[temp])
        {
            continue;
        }

        //the rpm is not installed, continue
        if (-1 != Rpms[temp].indexOf("not"))
        {
            continue;
        }

        //show the version in table
        Show += "<tr>";
        Show += "<td><input type='checkbox' value='" + RpmNames[temp] + "'></td>";
        Show += "<td>" + RpmNames[temp] + "</td><td>" + Rpms[temp].substr(RpmNames[temp].length + 1) + "</td>";
        Show += "</tr>";
    }
    Show += "</table>";
    Show += "<br\>";
    $('#rpm fieldset').append(Show);

    //add the update button
    var updateButton = createButton('Update');
    $('#rpm fieldset').append(updateButton);
    updateButton.bind('click', function(){
    		updateRpm();
    	});
}

function updateSelectAll()
{
    var check_status = $('#selectall').attr('checked');
    $('input:checkbox').attr('checked', check_status);
}

function updateRpm()
{
    var rpmPath = $('input[type=radio]:checked').val();
    var rpmPathType = "0";
    var rpms = "";
    var temp = "";

    if(undefined == rpmPath)
    {
        rpmPath = "";
    }

    //select other and we should use the value in the input
    if ("" == rpmPath)
    {
        //user input the repo, and we must stroe it in the cookie
        rpmPath = $('#repositoryaddr').val();
        rpmPathType = rpmPath;
    }
    else
    {
        if(-1 == rpmPath.toLowerCase().indexOf("devel"))
        {
            rpmPathType = "2";
        }
        else
        {
            rpmPathType = "1";;
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

    $('#update').show();
    if ("" == rpms)
    {
        $('#update').empty();
        $('#update').append("Please select the rpm!");
        return;
    }

    if ("" == rpmPath)
    {
        $('#update').empty();
        $('#update').append("Please select or input the repository!");
        return;
    }

    //remember users' choice and input
    $.cookie('xcatrepository', rpmPathType, { path: '/xcat', expires: 10 });

    $('#update').empty();
    $('#update').append("<p>Updating <b>" + rpms + "</b> from <b>" + rpmPath + "</b></p>");
    $('#update').append("<img id='loadingpic' src='images/throbber.gif'>");
    $('#rpm button').attr('disabled', 'true');

    // send the update command to server
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'update;' + rpms + ";" + rpmPath,
            msg : ''
        },

        success : ShowUpdateResult
    });
}

function ShowUpdateResult(data)
{
    var temp = 0;
	$('#loadingpic').remove();
    
    var resArray = data.rsp[0].split(/\n/);
    if (('' == resArray[resArray.length - 1]) && (resArray.length > 1)){
    	$('#update').append(resArray[resArray.length - 2]);
    }
    else{
    	$('#update').append(resArray[resArray.length - 1]);
    }

    $('#update').append('<br\><a>Response Detail:</a>');
    $('#update a').bind('click', function(){
    	$('#resDetail').show();
    });
    
    var resDetail = $('<div id="resDetail"></div>');
    resDetail.hide();
    $('#update').append(resDetail);
    
    for (temp = 0; temp < resArray.length; temp++)
    {
    	resDetail.append(resArray[temp] + "<br\>");
    }
    
    //update the rpm info
    $.ajax({
        url: 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpm -q xCAT-client perl-xCAT xCAT-server xCAT xCAT-rmc xCAT-UI'
        },

        success : showRpmInfo
    });
    
    $('#rpm button').attr('disabled', '');
    
}
/**
 * Load update page
 *
 * @return Nothing
 */
 function loadUpdatePage() {
    repositoryDiv = $('<div id="repository"></div>');
    rpmDiv = $('<div id="rpm"></div>');
    updateDiv = $('<div id="update"></div>');

    $('#content').append(repositoryDiv);
    $('#content').append(rpmDiv);
    $('#content').append(updateDiv);

    repositoryDiv.append("<h2>Repository</h2>");

    $.ajax( {
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'ostype'
        },

        success : showRepository
    });

    rpmDiv.append("<h2>xCAT Update Info<h2>");

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

    $('#repository').append(Show);

    //dispaly the Stable Repository, remember user's last selection
    Show = "<input type='radio' ";
    if(2 == $.cookie('xcatrepository'))
    {
        Show = Show + "checked='true'";
    }

    Show = Show + "name='reporadio' value='" + StableRepository + "'>";
    Show = Show + StableRepository + "(<strong>Stable</strong>)<br/>";

    $('#repository').append(Show);

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

    $('#repository').append(Show);
}

function showRpmInfo(data)
{
    var Rpms = null;
    var Show = "";
    var RpmNames = new Array("xCAT-client","perl-xCAT","xCAT-server","xCAT","xCAT-rmc","xCAT-UI");
    var temp = 0;
    if(null == data.rsp)
    {
        $('#rpm').append("Get Rpm Info Error!");
        return;
    }

    Rpms = data.rsp.split(/\n/);
    //no rpm installed, return
    if (1 > Rpms.length)
    {
        $('#rpm').append("No Rpm installed!");
        return;
    }

    Show = "<table id=rpmtable style='margin-left: 30px'>";
    Show += "<tr>";
    Show += "<td><input type='checkbox' id='selectall' value='' onclick='updateSelectAll()'></td>";
    Show += "<td>Package Name</td><td>Version</td>";
    Show += "</tr>";
    $('#rpm').append(Show);

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
        Show = "<tr>";
        Show += "<td><input type='checkbox' id='selectall' value='" + RpmNames[temp] + "'></td>";
        Show += "<td>" + RpmNames[temp] + "</td><td>" + Rpms[temp].substr(RpmNames[temp].length + 1) + "</td>";
        Show += "</tr>";
        $('#rpm').append(Show);
    }
    Show = "</table>";
    Show = "<br\>"
    Show += "<button onclick='updateRpm()'>Update</button>";
    $('#rpm').append(Show);
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
    $('#update').append("<p>update <b>" + rpms + "</b> from <b>" + rpmPath + "</b></p>");

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

    $('#update').append("Update finished.<br\>");
    for (temp = 0; temp < data.rsp.length; temp++)
    {
        $('#update').append(data.rsp[temp] + "<br\>");
    }
}
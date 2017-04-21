var globalNodesDetail = new Object();
var globalAllNodesNum = 0;
var globalFinishNodesNum = 0;
var globalTimeStamp;
var globalCondition = '';
var globalResponse = new Object();

function loadRmcMon() {
    // Find the rmcmon tab
    var rmcMonTab = $('#rmcmon');

    // Add the stauts bar first. id = 'rmcMonStatus'
    var rmcStatusBar = createStatusBar('rmcMonStatus');
    rmcStatusBar.find('div').append(createLoader());
    rmcMonTab.append(rmcStatusBar);

    // Add the configure button
    var configButton = createButton('Configure');
    configButton.hide();
    configButton.click(function() {
        if ($('#rmcMonConfig').is(':hidden')) {
            $('#rmcMonConfig').show();
        } else {
            $('#rmcMonConfig').hide();
        }
    });
    rmcMonTab.append(configButton);

    // Add configure div
    rmcMonTab.append("<div id='rmcMonConfig'></div>");
    $('#rmcMonConfig').hide();

    // Load the configure div's content
    loadRmcMonConfigure();

    // Add the content of the rmcmon
    rmcMonTab
            .append("<div id='rmcMonShow'><div id='rmcmonSummary'></div><div id='rmcmonDetail'></div><div id='nodeDetail'></div></div>");
    $('#nodeDetail').hide();

    // Check the software work status by platform (Linux and AIX)
    $.ajax({
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'ostype'
        },

        success : function(data) {
            data = decodeRsp(data);
            rsctRpmCheck(data);
        }
    });
}

function loadRmcMonConfigure() {
    // Get the configure div and clean its content
    var rmcmonCfgDiv = $('#rmcMonConfig');
    rmcmonCfgDiv.empty();

    // Add the start button
    var startButton = createButton('Start');
    rmcmonCfgDiv.append(startButton);
    startButton.click(function() {
        $('#rmcMonStatus div').empty().append(createLoader());
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'rmcstart;compute',
                msg : ''
            },

            success : function(data) {
                data = decodeRsp(data);
                $('#rmcMonStatus div').empty().append(data.rsp[0]);
            }
        });
    });

    // Add the stop button
    var stopButton = createButton('Stop');
    rmcmonCfgDiv.append(stopButton);
    stopButton.click(function() {
        $('#rmcMonStatus div').empty().append(createLoader());
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'monstop',
                tgt : '',
                args : 'rmcmon',
                msg : ''
            },

            success : function(data) {
                data = decodeRsp(data);
                $('#rmcMonStatus div').empty().append(data.rsp[0]);
            }
        });
    });

    // Add the cancel button
    var cancelButton = createButton('Cancel');
    rmcmonCfgDiv.append(cancelButton);
    cancelButton.click(function() {
        $('#rmcMonConfig').hide();
    });
}

function rsctRpmCheck(data) {
    // Linux has to check the rscp first
    if ('aix' != data.rsp) {
        $.ajax({
            url : 'lib/systemcmd.php',
            dataType : 'json',
            data : {
                cmd : 'rpm -q rsct.core'
            },

            success : function(data) {
                data = decodeRsp(data);
                if (-1 != data.rsp.indexOf("not")) {
                    $('#rmcMonStatus div')
                            .empty()
                            .append(
                                    'Please install the <a href="http://www14.software.ibm.com/webapp/set2/sas/f/rsct/rmc/download/home.html" target="install_window">RSCT</a> first.<br/>'
                                            + 'You can find more support from <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
                } else {
                    xcatrmcRpmCheck();
                }
            }
        });
    } else {
        xcatrmcRpmCheck();
    }
}

function xcatrmcRpmCheck() {
    $.ajax({
        url : 'lib/systemcmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpm -q xCAT-rmc rrdtool'
        },

        success : function(data) {
            data = decodeRsp(data);
            var softInstallStatus = data.rsp.split(/\n/);
            var needHelp = false;
            $('#rmcMonStatus div').empty();
            // Check the xcat-rmc
            if (-1 != softInstallStatus[0].indexOf("not")) {
                needHelp = true;
                $('#rmcMonStatus div')
                        .append(
                                'Please install the <a href="http://xcat.sourceforge.net/#download" target="install_window">xCAT-rmc</a> first.<br/>');
            }

            // Check the rrdtool
            if (-1 != softInstallStatus[1].indexOf("not")) {
                needHelp = true;
                $('#rmcMonStatus div')
                        .append(
                                'Please install the <a href="http://oss.oetiker.ch/rrdtool/download.en.html" target="install_window">RRD-tool</a> first.<br/>');
            }

            // Add help info or load the rmc show
            if (needHelp) {
                $('#rmcMonStatus div')
                        .append(
                                'You can find more support form <a href="http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf" target="pdf_window">xCAT2-Monitoring.pdf</a>');
            } else {
                rmcWorkingCheck();
            }
        }
    });
}

function rmcWorkingCheck() {
    $('#rmcMonStatus div').empty().append("Checking RMC working status");
    $('#rmcMonStatus div').append(createLoader());
    $('#rmcmon button:first').show();
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'monls',
            tgt : '',
            args : 'rmcmon',
            msg : ''
        },

        success : function(data) {
            data = decodeRsp(data);
            if (-1 != data.rsp[0].indexOf("not-monitored")) {
                $('#rmcMonStatus div').empty().append(
                        "Please start the RMC Monitoring first");
                return;
            }
            loadRmcMonShow();
        }
    });
}

function removeStatusBar() {
    if (globalAllNodesNum == globalFinishNodesNum) {
        $('#rmcMonStatus').remove();
    }

    $('#rmcmonDetail [title]').tooltip({
        position : [ 'center', 'right' ]
    });
}

function loadRmcMonShow() {
    $('#rmcMonStatus div').empty().append("Getting summary data");
    $('#rmcMonStatus div').append(createLoader());

    // Load the rmc status summary
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'rmcshow;summary;PctTotalTimeIdle,PctRealMemFree',
            msg : ''
        },

        success : function(data) {
            data = decodeRsp(data);
            showRmcSummary(data.rsp[0]);
        }
    });
}

function showRmcSummary(returnData) {
    var attributes = returnData.split(';');
    var attr;
    var attrName;
    var attrValues;
    var attrDiv;
    var summaryTable = $('<table><tbody></tbody></table>');
    var summaryRow;
    globalTimeStamp = new Array();

    // Update the rmc status area
    $('#rmcMonStatus div').empty().append("Getting nodes data").append(
            createLoader());
    // Load each nodes' status
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'rmcshow;compute;PctTotalTimeIdle,PctRealMemFree',
            msg : ''
        },

        success : function(data) {
            data = decodeRsp(data);
            parseRmcData(data.rsp);
        }
    });

    // Create the timestamp, the flot only use the UTC time, so had to change the value, to show the right time
    var tempDate = new Date();
    var tempOffset = tempDate.getTimezoneOffset();
    var tempTime = tempDate.getTime() - 3600000;
    for (var i = 0; i < 60; i++) {
        tempDate.setTime(tempTime + i * 60000);
        globalTimeStamp.push(tempDate.getTime());
    }

    // Show the summary data
    $('#rmcmonSummary').empty().append('<h3>Overview</h3><hr />');
    $('#rmcmonSummary').append(summaryTable);

    for (attr in attributes) {
        var tempTd = $('<td style="border:0px;padding:15px 5px;"></td>');
        var tempArray = [];
        var temp = attributes[attr].indexOf(':');
        attrName = attributes[attr].substr(0, temp);
        attrValues = attributes[attr].substr(temp + 1).split(',');

        if (0 == (attr % 3)) {
            summaryRow = $('<tr></tr>');
            summaryTable.append(summaryRow);
        }
        summaryRow.append(tempTd);
        attrDiv = $('<div id="monitor-sum-div' + attr
                + '" class="monitor-sum-div"></div>');
        tempTd.append(attrDiv);
        for (var i in attrValues) {
            tempArray.push([ globalTimeStamp[i], Number(attrValues[i]) ]);
        }

        $.jqplot('monitor-sum-div' + attr, [ tempArray ], {
            series : [ {
                showMarker : false
            } ],
            axes : {
                xaxis : {
                    label : attrName,
                    renderer : $.jqplot.DateAxisRenderer,
                    numberTicks : 5,
                    tickOptions : {
                        formatString : '%R',
                        show : true,
                        fontSize : '10px'
                    }
                },
                yaxis : {
                    tickOptions : {
                        formatString : '%.2f',
                        fontSize : '10px'
                    }
                }
            }
        });
    }
}

function parseRmcData(returnData) {
    var nodeName;
    var nodeStatus;

    $('#rmcmonDetail').empty().append('<h3>Detail</h3><hr/>');

    // Add the table for show nodes
    var detailUl = $('<ul style="margin:0px;padding:0px;"></ul>');
    // Update the table area
    $('#rmcmonDetail ul').remove();
    $('#rmcmonDetail').append(detailUl);

    globalAllNodesNum = returnData.length;
    globalFinishNodesNum = 0;
    for (var i in returnData) {
        var temp = returnData[i].indexOf(':');
        ;
        nodeName = returnData[i].substr(0, temp);
        nodeStatus = returnData[i].substr(temp + 1).replace(/(^\s*)|(\s*$)/g,
                '');

        if ('OK' != nodeStatus) {
            globalFinishNodesNum++;
            detailUl.append(createUnkownNode(nodeName));
            removeStatusBar();
            continue;
        }
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'rmcshow;' + nodeName
                        + ';PctTotalTimeIdle,PctRealMemFree',
                msg : nodeName
            },

            success : function(data) {
                data = decodeRsp(data);
                showRmcNodes(data.rsp, data.msg);
            }
        });
    }
}

function createUnkownNode(nodeName) {
    var tempLi = '<li class="monitor-unknown ui-corner-all monitor-node-li" id="'
            + nodeName
            + '" '
            + 'title="Name:'
            + nodeName
            + '<br/>Unknown"></li>';
    return tempLi;
}

function createErrorNode(nodeName) {
    var tempLi = '<li class="monitor-error ui-corner-all monitor-node-li id="'
            + nodeName + '" ' + 'title="Name:' + nodeName + '<br/>Error"></li>';
}

function showRmcNodes(data, nodename) {
    var attrname = '';
    var values = '';
    var position = 0;
    var index = 0;
    var classname = '';
    var tempObj = {};

    for (index in data) {
        position = data[index].indexOf(':');
        attrname = data[index].substr(0, position);
        values = data[index].substr(position + 1);
        // Error node, cannot get the last hour's data
        if (!values) {
            $('#rmcmonDetail ul').append(createErrorNode(nodename));
            if (globalNodesDetail[nodename]) {
                delete (globalNodesDetail[nodename]);
            }
            return;
        }

        // Normal node, save the values
        tempObj[attrname] = values;
    }

    globalNodesDetail[nodename] = tempObj;

    // Get each average
    var cpuAvg = 0;
    var memAvg = 0;
    var tempSum = 0;
    var tempArray = globalNodesDetail[nodename]['PctTotalTimeIdle'].split(',');
    for (index = 0; index < tempArray.length; index++) {
        tempSum += Number(tempArray[index]);
    }
    cpuAvg = parseInt(tempSum / index);

    tempArray = globalNodesDetail[nodename]['PctRealMemFree'].split(',');
    tempSum = 0;
    for (index = 0; index < tempArray.length; index++) {
        tempSum += Number(tempArray[index]);
    }
    memAvg = parseInt(tempSum / index);

    if (cpuAvg >= 10 && memAvg <= 90) {
        classname = 'monitor-normal';
    } else {
        classname = 'mornitor-warning';
    }

    var normalLi = $('<li class="' + classname
            + ' ui-corner-all monitor-node-li" id="' + nodename + '" title="'
            + 'Name:' + nodename + '<br/> CpuIdle: ' + cpuAvg
            + '%<br/> MemFree: ' + memAvg + '%"></li>');

    $('#rmcmonDetail ul').append(normalLi);
    normalLi.bind('click', function() {
        showNode($(this).attr('id'));
    });

    // Check if the process finished
    globalFinishNodesNum++;
    removeStatusBar();
}

function showNode(nodeName) {
    var nodeTable = $('<table><tbody></tbody></table>');
    var backButton = createButton('Go back to all nodes');
    var nodeRow;
    var parseNum = 0;

    $('#rmcmonDetail').hide();
    $('#nodeDetail').empty().show();
    $('#nodeDetail').append('<h3>' + nodeName + ' Detail</h3><hr />');
    $('#nodeDetail').append(backButton);
    backButton.bind('click', function() {
        $('#nodeDetail').hide();
        $('#rmcmonDetail').show();
    });

    $('#nodeDetail').append(nodeTable);

    for (var attr in globalNodesDetail[nodeName]) {
        var tempTd = $('<td style="border:0px;padding:1px 1px;"></td>');
        var attrChat = $('<div id="monitor-node-div' + nodeName + attr
                + '" class="monitor-node-div"></div>');
        if (0 == parseNum % 4) {
            nodeRow = $('<tr></tr>');
            nodeTable.append(nodeRow);
        }
        nodeRow.append(tempTd);
        parseNum++;

        tempTd.append(attrChat);
        var tempData = globalNodesDetail[nodeName][attr].split(',');
        var tempArray = [];
        for (var i in tempData) {
            tempArray.push([ globalTimeStamp[i], Number(tempData[i]) ]);
        }

        $.jqplot('monitor-node-div' + nodeName + attr, [ tempArray ], {
            series : [ {
                showMarker : false
            } ],
            axes : {
                xaxis : {
                    label : attr,
                    renderer : $.jqplot.DateAxisRenderer,
                    numberTicks : 5,
                    tickOptions : {
                        formatString : '%R',
                        show : true,
                        fontSize : '10px'
                    }
                },
                yaxis : {
                    tickOptions : {
                        formatString : '%.2f',
                        fontSize : '10px'
                    }
                }
            }
        });
    }
}

/**
 * Load the rmc event tab
 */
function loadRmcEvent() {
    // Find the rmcevent tab

    // Add the stauts bar first
    var rmcStatusBar = createStatusBar('rmcEventStatus');
    rmcStatusBar.find('div').append(createLoader());
    $('#rmcevent').append(rmcStatusBar);
    $('#rmcevent').append('<div id="rmcEventDiv"></div>');

    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'lsevent;-O;1000',
            msg : ''
        },

        success : function(data) {
            data = decodeRsp(data);
            showEventLog(data);
        }
    });
}

/**
 * Get all conditions
 */
function getConditions() {
    if (!globalCondition) {
        $('#rmcEventStatus div').empty()
                .append('Getting predefined conditions').append(createLoader());
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'lscondition',
                msg : ''
            },

            success : function(data) {
                data = decodeRsp(data);
                $('#rmcEventStatus div').empty();
                $('#rmcEventButtons').show();
                globalCondition = data.rsp[0];
            }
        });
    } else {
        $('#rmcEventButtons').show();
    }
}

/**
 * Get all response
 */
function getResponse() {
    var tempFlag = false;
    // Get all response first
    for (var i in globalResponse) {
        tempFlag = true;
        break;
    }

    if (!tempFlag) {
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'lsresponse',
                msg : ''
            },

            success : function(data) {
                data = decodeRsp(data);
                var resps = data.rsp[0].split(';');
                for (var i in resps) {
                    var name = resps[i];
                    name = name.substr(1, (name.length - 2));
                    globalResponse[name] = 1;
                }
            }
        });
    }
}

/**
 * Show all the event in the rmc event tab
 *
 * @param data Response from the xcat server
 */
function showEventLog(data) {
    $('#rmcEventStatus div').empty();
    // rsct not installed
    if (data.rsp[0] && (-1 != data.rsp[0].indexOf('lsevent'))) {
        $('#rmcEventStatus div').append('Please install RSCT first!');
        return;
    }
    var eventDiv = $('#rmcEventDiv');
    eventDiv.empty();

    // Get conditions and responses, save in the global
    getConditions();
    getResponse();

    var eventTable = new DataTable('lsEventTable');
    eventTable.init([ 'Time', 'Type', 'Content' ]);

    for (var i in data.rsp) {
        var row = data.rsp[i].split(';');
        eventTable.add(row);
    }

    eventDiv.append(eventTable.object());
    $('#lsEventTable').dataTable({
        'iDisplayLength': 50,
        'bLengthChange': false,
        "bScrollCollapse": true,
        "sScrollY": "400px",
        "sScrollX": "110%",
        "bAutoWidth": true,
        "oLanguage": {
            "oPaginate": {
              "sNext": "",
              "sPrevious": ""
            }
        }
    });

    // Add the configure button
    loadRmcEventConfig();

    // Unsort on the content column
    $('#lsEventTable thead tr th').eq(2).unbind('click');
}

/**
 * Add the configure button into rmc event tab
 */
function loadRmcEventConfig() {
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>');
    var chCondScopeLnk = $('<a>Change condition scope</a>');
    chCondScopeLnk.bind('click', function() {
        chCondScopeDia();
    });

    var mkCondRespLnk = $('<a>Make/remove associatione</a>');
    mkCondRespLnk.bind('click', function() {
        mkCondRespDia();
    });

    var startCondRespLnk = $('<a>Start/stop association</a>');
    startCondRespLnk.bind('click', function() {
        startStopCondRespDia();
    });

    // Actions
    var actionsLnk = '<a>Actions</a>';
    var actsMenu = createMenu([ chCondScopeLnk, mkCondRespLnk, startCondRespLnk ]);

    // Create an action menu
    var actionsMenu = createMenu([ [ actionsLnk, actsMenu ] ]);
    actionsMenu.superfish();
    actionsMenu.css('display', 'inline-block');
    actionBar.append(actionsMenu);

    // Create a division to hold actions menu
    var menuDiv = $('<div id="lsEventTable_menuDiv" class="menuDiv"></div>');
    $('#lsEventTable_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);
    $('#lsEventTable_filter').appendTo(menuDiv);
}

/**
 * Show the make association dialogue
 */
function mkCondRespDia() {
    var diaDiv = $('<div title="Configure Association" id="mkAssociation" class="tab"></div>');
    var mkAssociationTable = '<center><table><thead><tr><th>Condition Name</th><th>Response Name</th></tr></thead>';
    mkAssociationTable += '<tbody><tr><td id="mkAssCond">';
    // Add the conditions into fieldset
    if (!globalCondition) {
        mkAssociationTable += 'Getting predefined conditions, open this dislogue later';
    } else {
        mkAssociationTable += createConditionTd(globalCondition);
    }

    mkAssociationTable += '</td><td id="mkAssResp">Please select condition first</td></tr></tbody></table></center>';
    diaDiv.append(mkAssociationTable);
    diaDiv.append('<div id="selectedResp" style="display: none;" ><div>');
    // Change the response field when click the condition
    diaDiv.find('input:radio').bind('click',
        function() {
            diaDiv.find('#mkAssResp').empty().append('Getting response').append(createLoader());
            $.ajax({
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : 'lscondresp;"'
                            + $(this).attr('value') + '"',
                    msg : ''
                },

                success : function(data) {
                    data = decodeRsp(data);
                    var tempHash = new Object();
                    var oldSelectedResp = '';
                    var showStr = '';
                    if (data.rsp[0]) {
                        var names = data.rsp[0].split(';');
                        for (var i in names) {
                            var name = names[i];
                            name = name.substr(1,
                                    name.length - 2);
                            tempHash[name] = 1;
                        }
                    }

                    for (var name in globalResponse) {
                        if (tempHash[name]) {
                            showStr += '<input type="checkbox" checked="checked" value="'
                                    + name
                                    + '">'
                                    + name
                                    + '<br/>';
                            oldSelectedResp += ';' + name;
                        } else {
                            showStr += '<input type="checkbox" value="'
                                    + name
                                    + '">'
                                    + name
                                    + '<br/>';
                        }
                    }

                    diaDiv.find('#mkAssResp').empty()
                            .append(showStr);
                    diaDiv.find('#selectedResp').empty()
                            .append(oldSelectedResp);
                }
            });
        });

    diaDiv.dialog({
        modal : true,
        width : 620,
        height : 600,
        close : function(event, ui) {
            $(this).remove();
        },
        buttons : {
            'Ok' : function() {
                var newResp = new Object();
                var oldResp = new Object();
                var oldString = '';
                var newString = '';

                // Get the old seelected responses
                var conditionName = $(this).find('#mkAssCond :checked').attr(
                        'value');
                if (!conditionName) {
                    return;
                }
                var temp = $(this).find('#selectedResp').html();
                if (!temp) {
                    return;
                }
                var tempArray = temp.substr(1).split(';');
                for (var i in tempArray) {
                    oldResp[tempArray[i]] = 1;
                }

                // Get the new selected responses
                $(this).find('#mkAssResp input:checked').each(function() {
                    var respName = $(this).attr('value');
                    newResp[respName] = 1;
                });

                for (var i in newResp) {
                    if (oldResp[i]) {
                        delete oldResp[i];
                        delete newResp[i];
                    }
                }

                // Add the response which are delete
                for (var i in oldResp) {
                    oldString += ',"' + i + '"';
                }
                if ('' != oldString) {
                    oldString = oldString.substr(1);
                }

                // Add the response which are new add
                for (var i in newResp) {
                    newString += ',"' + i + '"';
                }
                if ('' != newString) {
                    newString = newString.substr(1);
                }

                if (('' != oldString) || ('' != newString)) {
                    $('#rmcEventStatus div').empty().append(
                            'Create/remove associations ').append(
                            createLoader());
                    $.ajax({
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : 'mkcondresp;"' + conditionName + '";+'
                                    + newString + ':-' + oldString,
                            msg : ''
                        },

                        success : function(data) {
                            data = decodeRsp(data);
                            $('#rmcEventStatus div').empty()
                                    .append(data.rsp[0]);
                            ;
                        }
                    });
                }
                $(this).dialog('destroy').remove();
            },
            'Cancel' : function() {
                $(this).dialog('destroy').remove();
            }
        }
    });
}

/**
 * Show the make condition dialogue
 */
function chCondScopeDia() {
    var diaDiv = $('<div title="Change Condition Scope" id="chScopeDiaDiv" class="tab"></div>');
    var tableContent = '<center><table id="changeScopeTable" ><thead><tr><th>Condition Name</th><th>Group Name</th></tr></thead>';

    tableContent += '<tbody><tr><td id="changePreCond">';
    // Add the conditions into fieldset
    if ('' == globalCondition) {
        tableContent += 'Getting predefined conditions, open this dialogue later';
    } else {
        tableContent += createConditionTd(globalCondition);
    }
    tableContent += '</td><td id="changeGroup">';

    // Add the groups into table
    var groups = $.cookie('groups').split(',');
    for (var i in groups) {
        tableContent += '<input type="checkbox" value="' + groups[i] + '">'
                + groups[i] + '<br/>';
    }

    tableContent += '</td></tr></tbody></table></center>';
    diaDiv.append(tableContent);
    // Fieldset to show status
    diaDiv.append('<fieldset id="changeStatus"></fieldset>');
    // Create the dislogue
    diaDiv.dialog({
        modal : true,
        width : 500,
        height : 600,
        close : function(event, ui) {
            $(this).remove();
        },
        buttons : {
            'Ok' : function() {
                $('#changeStatus').empty().append('<legend>Status</legend>');
                var conditionName = $('#changePreCond :checked').attr('value');
                var groupName = '';
                $('#changeGroup :checked').each(function() {
                    if ('' == groupName) {
                        groupName += $(this).attr('value');
                    } else {
                        groupName += ',' + $(this).attr('value');
                    }
                });

                if (undefined == conditionName) {
                    $('#changeStatus').append('Please select conditon');
                    return;
                }

                if ('' == groupName) {
                    $('#changeStatus').append('Please select group');
                    return;
                }

                $('#changeStatus').append(createLoader());
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'mkcondition;change;' + conditionName + ';'
                                + groupName,
                        msg : ''
                    },

                    success : function(data) {
                        data = decodeRsp(data);
                        $('#changeStatus img').remove();
                        if (-1 != data.rsp[0].indexOf('Error')) {
                            $('#changeStatus').append(data.rsp[0]);
                        } else {
                            $('#rmcEventStatus div').empty()
                                    .append(data.rsp[0]);
                            $('#chScopeDiaDiv').remove();
                        }
                    }
                });
            },
            'Cancel' : function() {
                $(this).dialog('destroy').remove();
            }
        }
    });
}

/**
 * Show the make response dialogue
 */
function mkResponseDia() {
    var diaDiv = $('<div title="Make Response"><div>');
    diaDiv.append('Not yet supported.');

    diaDiv.dialog({
        modal : true,
        width : 400,
        close : function(event, ui) {
            $(this).remove();
        },
        buttons : {
            'Ok' : function() {
                $(this).dialog('destroy').remove();
            },
            'Cancel' : function() {
                $(this).dialog('destroy').remove();
            }
        }
    });
}

/**
 * Start the condition and response associations
 */
function startStopCondRespDia() {
    var diaDiv = $('<div title="Start/Stop Association" id="divStartStopAss" class="tab"><div>');
    diaDiv.append('Getting conditions').append(createLoader());

    if (!globalCondition) {
        $.ajax({
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : 'lscondition',
                msg : ''
            },

            success : function(data) {
                data = decodeRsp(data);
                if (data.rsp[0]) {
                    globalcondition = data.rsp[0];
                    $('#divStartStopAss').empty().append(
                            createAssociationTable(globalCondition));
                    $('#divStartStopAss')
                            .dialog("option", "position", 'center');
                } else {
                    $('#divStartStopAss').empty().append(
                            'There are no conditions');
                }
            }
        });
    } else {
        diaDiv.empty().append(createAssociationTable(globalCondition));
    }

    diaDiv.dialog({
        modal : true,
        width : 570,
        height : 600,
        close : function(event, ui) {
            $(this).remove();
        },
        buttons : {
            'Close' : function() {
                $(this).dialog('destroy').remove();
            }
        }
    });

    $('#divStartStopAss button').bind(
            'click',
            function() {
                var operationType = '';
                var conditionName = $(this).attr('name');
                if ('Start' == $(this).html()) {
                    operationType = 'start';
                } else {
                    operationType = 'stop';
                }

                $(this).parent().prev().empty().append(createLoader());
                $('#divStartStopAss').dialog('option', 'disabled', true);
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : operationType + 'condresp;' + conditionName,
                        msg : operationType + ';' + conditionName
                    },

                    success : function(data) {
                        data = decodeRsp(data);
                        var conditionName = '';
                        var newOperationType = '';
                        var associationStatus = '';
                        var backgroudColor = '';
                        if ('start' == data.msg.substr(0, 5)) {
                            newOperationType = 'Stop';
                            conditionName = data.msg.substr(6);
                            associationStatus = 'Monitored';
                            backgroudColor = '#ffffff';
                        } else {
                            newOperationType = 'Start';
                            conditionName = data.msg.substr(5);
                            associationStatus = 'Not Monitored';
                            backgroudColor = '#fffacd';
                        }

                        var button = $('#divStartStopAss button[name="'
                                + conditionName + '"]');
                        if (data.rsp[0]) {
                            $('#rmcEventStatus div').empty().append(
                                    'Getting associations\' status').append(
                                    createLoader());
                            $('#rmcEventButtons').hide();
                            button.html(newOperationType);
                            button.parent().prev().html(associationStatus);
                            button.parent().parent().css('background-color',
                                    backgroudColor);
                            globalCondition = '';
                            getConditions();
                        } else {
                            button.html('Error');
                        }

                        $('#divStartStopAss').dialog('option', 'disabled',
                                false);
                    }
                });
            });
}

/**
 * Stop the condition and response associations
 */
function stopCondRespDia() {
    var diaDiv = $('<div title="Stop Association" id="stopAss"><div>');
    diaDiv.append('Getting conditions').append(createLoader());

    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'lscondition;-m',
            msg : ''
        },

        success : function(data) {
            data = decodeRsp(data);
            if (data.rsp[0]) {
                $('#stopAss').empty().append(
                        createConditionTable(data.rsp[0]));
                $('#stopAss').dialog("option", "position", 'center');
            } else {
                $('#stopAss').empty().append(
                        'There is not monitored condition.');
            }
        }
    });

    diaDiv.dialog({
        modal : true,
        width : 570,
        close : function(event, ui) {
            $(this).remove();
        },
        buttons : {
            'Stop' : function() {
                var conditionName = $('#stopAss :checked').attr('value');
                if (!conditionName) {
                    alert('Select condition name please.');
                    return;
                }
                $('#rmcEventStatus div').empty().append(
                        'Stoping monitor on ' + conditionName).append(
                        createLoader());
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'stopcondresp;' + conditionName,
                        msg : ''
                    },

                    success : function(data) {
                        data = decodeRsp(data);
                        $('#rmcEventStatus div').empty().append(data.rsp[0]);
                    }
                });
                $(this).dialog('destroy').remove();
            },
            'Cancel' : function() {
                $(this).dialog('destroy').remove();
            }
        }
    });
}

/**
 * Create the condition table for dialogue
 *
 * @param cond Condition
 */
function createConditionTd(cond) {
    var conditions = cond.split(';');
    var name = '';
    var showStr = '';
    for (var i in conditions) {
        name = conditions[i];
        // Because there is status and quotation marks in name,
        // we must delete the status and quotation marks
        name = name.substr(1, name.length - 6);
        showStr += '<input type="radio" name="preCond" value="' + name + '">' + name + '<br/>';
    }

    return showStr;
}

/**
 * Create the association table for dialogue, which show the status and start/stop associations
 *
 * @param cond Condition
 */
function createAssociationTable(cond) {
    var conditions = cond.split(';');
    var name = '';
    var tempLength = '';
    var tempStatus = '';
    var showStr = '<center><table><thead><tr><th>Condition Name</th><th>Status</th><th>Start/Stop</th></tr></thead>';
    showStr += '<tbody>';

    for (var i in conditions) {
        name = conditions[i];
        tempLength = name.length;
        tempStatus = name.substr(tempLength - 3);
        name = name.substr(1, tempLength - 6);

        if ('Not' == tempStatus) {
            showStr += '<tr style="background-color:#fffacd;"><td>' + name
                    + '</td><td>Not Monitored</td>';
            showStr += '<td><button id="button" name="' + name
                    + '">Start</button></td>';
        } else {
            showStr += '<tr><td>' + name + '</td><td>Monitored</td>';
            showStr += '<td><button id="button" name="' + name
                    + '">Stop</button></td>';
        }
        showStr += '</tr>';
    }

    showStr += '<tbody></table></center>';

    return showStr;
}
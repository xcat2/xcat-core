/* xCAT WebUI authentication handling functions/setup */
/* IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html */
function openlogdialog (data, textstatus) { //open the log in dialog if not logged in
    if (data.authenticated == "no") {
        logdialog.dialog("open");
    }
}

function onlogin (data, textstatus) {
    $("#password").val(""); //clear the password field regardless of what happens
    if (data.authenticated == "yes") {
        $("#logstatus").text("Logged in successfully");
        nrtree.refresh(); // Fix tree potentiall broken through attempts to operate without auth
        logdialog.dialog("close");
    } else {
        $("#logstatus").text("Authentication failure");
        $("#logstatus").css("color","#ff0000");
    }
}

function logout () {
    $.post("log.php",{logout:1})
    $("#logstatus").html("");
    logdialog.dialog("open");
}

function authenticate() {
    $("#logstatus").css("color","#000000");
    $("#logstatus").html('Authenticating...<img src="images/throbber.gif"/>');
    var passwd=$("#password").val();
    $.post("log.php",{
            username: $("#username").val(),
            password: passwd
        },onlogin,"json");
}

$(document).ready(function() {
    logdialog=$("#logdialog").dialog({
        modal: true,
        closeOnEscape: false,
        closebutton: false,
        overlay: {
            backgroundColor: "#000",
            opacity: 1

        },
        height: 200,
        width: 350,
        autoOpen: false,
        buttons: {
            "Log In": authenticate
            },
        open: function(type, dialog) {
            if (document.location.protocol == "http:") {
                $("#logstatus").html("Unencrypted Session!");
                $("#logstatus").css("color","#ff0000");
            }
            if ($("#username").val() == "") {
                $("#username").focus();
            } else {
                $("#password").focus();
            }
        },
    });

    $("#username").keydown(function(event) { //When 'enter' is hit while in username, advance to password
        if (event.keyCode==13) {
            $("#password").focus();
        }
    });
    $("#password").keydown(function(event) { //Submit authentication if enter is pressed in password field
        if (event.keyCode==13) {
            authenticate();
        }
    });

    $("#login").click(function(event) { //Also authenticate when 'log in' button is activated
        authenticate();
    });

    $("#logout").click(function(event) { //Bind the button with logout id to our logout function
        logout();
    });

    $.post("log.php",{},openlogdialog,"json"); //Determine if authentication dialog is currently needed on load
});

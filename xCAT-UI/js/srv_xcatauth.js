/**
 * Open login dialog
 */
$(document).ready(function() {
    $('#header').remove();
    $('#content').remove();

    var winHeight = document.body.clientHeight;
    var diagHeight = $('#login').css('height');
    diagHeight = diagHeight.substr(0, diagHeight.length - 2);
    diagHeight = Number(diagHeight);

    // The window's height is to small to show the dialog
    var tmpHeight = 0;
    if ((winHeight - 50) < diagHeight){
        tmpHeight = 0;
    } else {
        tmpHeight = parseInt((winHeight - diagHeight - 50) / 2);
    }

    $('#login').css('margin', tmpHeight + 'px auto');
    $('button').bind('click', function(){
        authenticate();
    }).button();

    if (document.location.protocol == 'http:') {
        $('#login-status').html('You are using an unencrypted session!');
        $('#login-status').css('color', 'red');
    }

    if (!$("#login input[name='username']").val()) {
        $("#login input[name='username']").focus();
    } else {
        $("#login input[name='password']").focus();
    }

    // When enter is hit while in username, advance to password
    $("#login input[name='username']").keydown(function(event) {
        if (event.keyCode == 13) {
            $("#login input[name='password']").focus();
        }
    });

    // Submit authentication if enter is pressed in password field
    $("#login input[name='password']").keydown(function(event) {
        if (event.keyCode == 13) {
            authenticate();
        }
    });
});

/**
 * Update login dialog
 *
 * @param data Data returned from AJAX call
 * @param txtStatus Status of login
 */
function onlogin(data, txtStatus) {
    // Clear password field regardless of what happens
    var usrName = $("#login input[name='username']").val();
    $("#login input[name='password']").val('');
    if (data.authenticated == 'yes') {
        $('#login-status').text('Login successful');
        window.location = 'service.php';

        // Set user name cookie
        var exDate = new Date();
        exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
        $.cookie('xcat_username', usrName, { expires: exDate, path: '/xcat', secure:true });
    } else {
        $('#login-status').text('Authentication failure');
        $('#login-status').css('color', '#FF0000');
    }
}

/**
 * Authenticate user for new session
 */
function authenticate() {
    $('#login-status').css('color', '#000000');
    $('#login-status').html('Authenticating...');

    var passwd = $("#login input[name='password']").val();
    $.post('lib/srv_log.php', {
        username : $("#login input[name='username']").val(),
        password : passwd
    }, onlogin, 'json');
}

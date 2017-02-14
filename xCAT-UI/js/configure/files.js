/**
 * Load the files page
 */
function loadFilesPage() {
    var tabId = 'filesTab';
    $('#' + tabId).empty();
    
    // Set padding for page
    $('#' + tabId).css('padding', '10px 30px');
    
    // Create info bar
    var info = $('#' + tabId).find('.ui-state-highlight');
    // If there is no info bar
    if (!info.length) {
        var infoBar = createInfoBar('Below is a listing of the xCAT repository. ' +
                'Upload any file or package into the repository using the Upload button. ' + 
                'Go into any subdirectories by specifying the directory path and clicking on Go.');       
        
        var directoryFS = $('<fieldset></fieldset>');
        var dirLegend = $('<legend>Directory</legend>');
        directoryFS.append(dirLegend);
        
        // Division to hold directory actions
        var actions = $('<div></div>');
        directoryFS.append(actions);
        
        // Create button to create a directory
        var folderBtn = createButton('New folder');
        folderBtn.click(function() {
            var deleteFolderBtn = $('<span class="ui-icon ui-icon-close" style="margin-left:10px; margin-right:10px;"></span>');
            var createFolderBtn = createButton('Create');
            
            // Create a new directory
            var newFolder = $('<li><span class="ui-icon ui-icon-folder-collapsed" style="margin-right: 10px;"></span><input type="text" name="new_folder"/></li>');
            newFolder.prepend(deleteFolderBtn);
            newFolder.append(createFolderBtn);
            $('#repo_content ul').append(newFolder);
            
            // Delete new folder on-click
            deleteFolderBtn.click(function() {
                $(this).parents('li').remove();
            });
            
            // Create folder on-click
            createFolderBtn.click(function() {
                var directory = $('#' + tabId + ' input[name="repo_directory"]');
                var newFolderPath = $('#' + tabId + ' input[name="new_folder"]').val();
                if (newFolderPath) {
                    $.ajax({
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : 'createfolder;' + directory.val() + '/' + newFolderPath,
                            msg : ''
                        },
                     
                        success:function(data) {
                            openDialog('info', data.rsp[0]);
                        }
                    });
                    
                    $(this).parents('li').remove();
                } else {
                    openDialog('warn', 'You must specify the folder name');
                }
            });
        });
        
        // Create button to upload files
        var uploadBtn = createButton('Upload');
        uploadBtn.click(function() {
            var directory = $('#' + tabId + ' input[name="repo_directory"]');
            openUploadDialog(directory.val());
        });
        
        // Create button to go into a directory path
        var dirPath = $('<input type="text" name="repo_directory" style="width:400px;"/>');
        var goBtn = createButton('Go');
        goBtn.click(function() {
            var directory = $('#' + tabId + ' input[name="repo_directory"]');
            loadPath(directory.val());
        });
        goBtn.attr('id', 'go_to_path');
        
        var space = $('<div id="repo_space"></div>');
        var content = $('<div id="repo_content" class="form"></div>');        
        actions.append(folderBtn, uploadBtn, dirPath, goBtn);
        directoryFS.append(space, content);
        
        $('#' + tabId).append(infoBar, directoryFS);
    }
    
    // Retrieve repository space 
    getRepositorySpace();
        
    // Retrieve files from /install
    loadPath('/install');
}

/**
 * Get the repository space
 */
function getRepositorySpace() {
    // Grab repository space
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        async: false,
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'getrepospace',
            msg : ''
        },
        success: function(data) {
            $('#repo_space').children().remove();
            
            // Data returned is: size, used, available, used %, mount
            // Data could be in a different format in CMO, where it puts the directory on the line
            // "rsp":["\/data\/xcat\/install 28G 6.0G 20G 24% \/install"],"msg":null}
            var space = data.rsp[0].split(' ');
            if (space.length == 6) {
                space.splice(0,1);
            }
            var spaceLabel = $('<label style="margin:10px;width:300px;"><b>Total size: </b>' + space[0] +
                    '<b> | Available: </b>' + space[2] +
                    '</label>');
            $('#repo_space').append(spaceLabel);
        }
    });
}

/**
 * Open a dialog to upload files into the repository
 * 
 * @param destDirectory The destination directory
 */
function openUploadDialog(destDirectory) {
    // Create info bar
    var info = createInfoBar('Select a file to upload onto ' + destDirectory + '.');
    var dialog = $('<div id="upload_file_dg"></div>');
    dialog.append(info);
    
    // Upload file
    var upload = $('<form id="upload_file" enctype="multipart/form-data"></form>');
    var label = $('<label style="margin-right: 10px;">Remote file:</label>');
    var file = $('<input type="file" name="file" id="file"/>');
    var subBtn = createButton('Upload');    
    upload.append(label, file, subBtn);
    dialog.append(upload);
    
    upload.submit(function() {
        // Create status bar, hide on load
        var statBarId = 'uploadStatusBar';
        var statBar = createStatusBar(statBarId);
        var loader = createLoader('');
        statBar.find('div').append('Do not close this dialog while the file is being uploaded ');
        statBar.find('div').append(loader);
        statBar.prependTo($('#upload_file_dg'));        
        
        var data = new FormData($('#upload_file')[0]);
        $.ajax({
            type: 'POST',
            url : 'lib/uploadfile.php?destination=' + destDirectory,
            data: data,
            success: function(data) {
                $('#uploadStatusBar').find('img').hide();
                $('#uploadStatusBar').find('div').empty();
                $('#uploadStatusBar').find('div').append(data);  
                
                // Refresh directory contents
                $('#go_to_path').click();
                getRepositorySpace();
            },
            cache: false,
            contentType: false,
            processData: false
        });
        
        return false;
    });
    
    // Create dialog    
    dialog.dialog({
        modal: true,
        title: 'Upload',
        width: 500,
        close: function() {$(this).remove();}
    });
}

/**
 * Load the directory path structure
 * 
 * @path The directory path
 */
function loadPath(path) {
    // Limit access to only /install
    if (path.substring(0, 9).indexOf("install") == -1) {
        openDialog('warn', 'You are not authorized to browse outside the repository');
        return;
    }
    
    var tabId = 'filesTab';
    var directory = $('#' + tabId + ' input[name="repo_directory"]');
    directory.val(path);
    
    // Un-ordered list containing directories and files
    var contentId = 'repo_content';
    $('#' + contentId).empty();
    var itemsList = $('<ul></ul>');
    $('#' + contentId).append(itemsList);
    
    // Back button to go up a directory
    var item = $('<li><span class="ui-icon ui-icon-folder-collapsed" style="margin-right: 10px;"></span>..</li>');
    itemsList.append(item);
    item.dblclick(function() {
        if (path.lastIndexOf('/') > 1)
            path = path.substring(0, path.lastIndexOf('/'));
        loadPath(path);
    });
    
    $.ajax({
        type: 'POST',
        url : 'lib/getpath.php',
        dataType : 'json',
        data: {
            action: 'browse',
            path: path,
            time: new Date().getTime()
        },
        beforeSend: function() {
            // Show loading image
        },
        success: function(files) {
            $.each(files, function(index, file) {
                if (!file.path || file.path.indexOf("undefined"))
                    file.path = "";
                
                var fullPath = file.path + "/" + file.name;
                
                // Create a list showing the directories and files
                var item;
                if (file.isFolder) {
                    var deleteFolderBtn = $('<span class="ui-icon ui-icon-close" style="margin-left:10px; margin-right:10px;"></span>');
                    
                    item = $('<li><span class="ui-icon ui-icon-folder-collapsed" style="margin-right: 10px;"></span>' + file.name + '</li>');
                    item.prepend(deleteFolderBtn);                    
                    itemsList.append(item);
                    item.dblclick(function() {
                        loadPath(directory.val() + fullPath);
                    });
                    
                    // Delete file on click
                    deleteFolderBtn.click(function() {
                        deleteFile($(this).parents('li'), directory.val() + fullPath);
                    });
                } else {
                    var icon = $('<span class="ui-icon ui-icon-document" style="margin-right: 10px;"></span>');
                    var deleteFileBtn = $('<span class="ui-icon ui-icon-close" style="margin-left:10px; margin-right:10px;"></span>');
                    
                    item = $('<li><a href="' + directory.val() + fullPath + '">' + file.name + '</a></li>');
                    item.append(deleteFileBtn, icon);
                    
                    // Delete file on click
                    deleteFileBtn.click(function() {
                        deleteFile($(this).parents('li'), directory.val() + fullPath);
                    });
                    
                    itemsList.append(item);
                }                    
            });
        }     
    });
}

/**
 * Prompt user to confirm deletion of file 
 * 
 * @param container The element container
 * @param file The file name to delete
 */
function deleteFile(container, file) {
    // Open dialog to confirm
    var confirmDialog = $('<div id="confirm_delete"></div>');
    var warn = createWarnBar('Are you sure you want to delete ' + file + '?');
    confirmDialog.append(warn);
    confirmDialog.dialog({
        title: "Confirm",
        modal: true,
        width: 400,
        close: function() {$(this).remove();},
        buttons: {
            "Ok": function() {
                var loader = createLoader('').css({'margin': '5px'});
                $(this).append(loader);
                
                // Change dialog buttons
                $(this).dialog('option', 'buttons', {
                    'Close':function() {
                        $(this).dialog('destroy').remove();
                    }
                });
                                
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    async: false,
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'deletefile;' + file,
                        msg : ''
                    },
                    success: function(data) {
                        $('#confirm_delete').children().remove();
                        var info = createInfoBar(data.rsp[0]);
                        $('#confirm_delete').append(info);
                        getRepositorySpace();
                    }
                });
                
                // Delete folder from the list
                container.remove();
            },
            "Cancel": function() {
                $(this).dialog('destroy').remove();
            }
        }
    });
}
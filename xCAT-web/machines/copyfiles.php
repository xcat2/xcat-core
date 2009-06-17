<?php
// Show some key attributes of the selected nodes
$TOPDIR = '..';
$expire_time = gmmktime(0,0,0,1,1,2038);

require_once "$TOPDIR/lib/functions.php";

// Get the noderange
$noderange = @$_REQUEST['noderange'];
if(empty($noderange)) { echo "<p>Select one or more groups or nodes.</p>\n"; exit; }

?>

</script>

<FORM NAME=copyForm>

<p>Select the files, copy from or to multiple nodes.
In addtion, an option is provided to use rsync to update the files on the nodes,
or to an installation image on the local node.
</p>

<script type="text/javascript">
$.ui.dialog.defaults.bgiframe = true;
var diagOpts = {
    bgiframe: true,
    modal: true,
    //autoOpen: false,
};
$(function() {
    $("#copyDialog").dialog(diagOpts);
});

function copydialog() {
    $("#copyDialog").dialog("show");
}

</script>

<?php insertButtons(array('label' => 'Copy Files', 'id'=> 'copyButton', 'onclick' => 'copydialog()')); ?>

<div id="copyDialog" title="This is the tile" class="flora"></div>

<h3>Options:</h3>
<TABLE id=inner_table  cellspacing=0 cellpadding=5>
<TR>
      <TD valign=top nowrap><label><INPUT type=checkbox name=serial id=serial>Streaming mode</label></TD>
      <TD>Specifies that output is returned as it becomes available from each target, instead of waiting for the command to be completed on a target before returning output from that target.</TD>
</TR>

<TR>
      <TD valign=top nowrap><label><INPUT type=checkbox name=monitor id=monitor>Monitor</label></TD>
      <TD>Prints starting and completion messages for each node.  Useful with Streaming mode.</TD>
</TR>

 <TR>
      <TD valign=top nowrap><label><INPUT type=checkbox name=verify id=verify>Verify</label></TD>
      <TD>Verifies that nodes are responding before sending the command to them.</TD>
</TR>

<TR>
      <TD valign=top nowrap><label><INPUT type=checkbox name=collapse id=collapse disabled>Collaspe Identical Output</label></TD>
      <TD>Automatically pipe the xdsh output into xdshbak which will only display output once for all the nodes that display identical output.  See the xdshbak man page for more info.</TD>
</TR>

<TR>
      <TD valign=top nowrap>Fanout: <INPUT type=text name=fanout id=fanout></TD>
      <TD>The maximum number of nodes the command should be run on concurrently. When the command finishes on 1 of the nodes, it will be started on an additional node (the default is 64).</TD>
</TR>

<TR>
      <TD valign=top nowrap>UserID: <INPUT type=text name=userID id=userID></TD>
      <TD>The user id to use to run the command on the nodes.</TD>
</TR>

<TR>
      <TD valign=top nowrap>Remote Shell: <INPUT type=text name=rshell id=rshell></TD>
      <TD>The remote shell program to use to run the command on the nodes. The default is /usr/bin/ssh.</TD>
</TR>

<TR>
      <TD valign=top nowrap>Shell Options: <INPUT type=text name=shell_opt id=shell_opt></TD>
      <TD>Options to pass to the remote shell being used.</TD>
</TR>

<TR>
       <TD valign=top nowrap><label><INPUT type=checkbox name=ret_code id=ret_code>Return Code</label></TD>
      <TD>Prints the return code of the (last) command that was run remotely on each node. The return code is appended at the end of the output for each node.</TD>
</TR>

</TABLE>


<h3>Tips:</h3>
<UL>
<li>See the <a href="<?php echo getDocURL('manpage','xdcp.1'); ?>">xdcp man page</a> for more information about this command.</li>
</UL>

</FORM>

<?php
insertNotDoneYet();
?>

<?php
/*------------------------------------------------------------------------------
  Produce the page for running commands on the nodes of the cluster
------------------------------------------------------------------------------*/
$TOPDIR = '..';
$expire_time = gmmktime(0, 0, 0, 1, 1, 2038);
//setcookie('history[]', "date;hello.sh", $expire_time);

require_once "$TOPDIR/lib/functions.php";

if (!isset($_REQUEST['intab'])) {
insertHeader('Run Commands on Nodes', array('dsh.css'),
			array('dsh.js'),
			array('manage','dsh'));
echo "<div id=content>\n";
}
else {		// if loading in the tabs, still need to load dsh.js (dsh.css must be loaded in the <head> section and therefore must be loaded by groups.php)
	echo "<script type='text/javascript' src='$TOPDIR/manage/dsh.js'></script>\n";
}

echo "<FORM NAME=dshForm id=dshForm>\n";

if (isset($_REQUEST['noderange']) && !isset($_REQUEST['intab'])) {
	echo "<p><B><FONT size='+1'>Run Command on: </FONT></B>";
	if (strlen($_REQUEST['noderange']) > 70) {
		echo "<TEXTAREA rows=1 cols=70 readonly name=nodeList id=nodeList>" . $_REQUEST['noderange'] . "</TEXTAREA></p>\n";
	} else {
		echo "<INPUT size=70 type=text name=nodeList id=nodeList value='" . $_REQUEST['noderange'] . "'></p>\n";
	}
}

echo "<P>Select a previous command from the history, or enter the command and options below. Then click on Run Cmd.</P>\n";

insertButtons(array('label' => 'Run Cmd', 'id' => 'runcmdButton', 'onclick' => 'opencmddialog()'));

if (!isset($_REQUEST['noderange']) && !isset($_REQUEST['intab'])) {
	echo "<p>Run Command on Group:<SELECT name=nodegrps id=nodegrps><OPTION value=''>Choose ...</OPTION>\n";
  	$nodegroups = getGroups();
	foreach ($nodegroups as $group) {
		//if($group == $currentGroup) { $selected = 'selected'; } else { $selected = ''; }
		echo "<OPTION value='$group' $selected>$group</OPTION>\n";
		}
	echo "</SELECT></p>\n";
}

?>
    <p>Command: <INPUT size=60 type=text name=command id=command> History:
      <SELECT name=history onChange="_setvars();">
      <OPTION value="">Choose ...</OPTION>
      <?php
		if (isset($_COOKIE['history'])) {
			foreach ($_COOKIE['history'] as $value) { echo "<option value='$value'>$value</option>\n"; }
		}
	 ?>
     </SELECT>

    <p><label><INPUT type=checkbox name=copy_script id=copy_script>
		Copy command to nodes (The command specified above will 1st be copied
      	to /tmp on the nodes and executed from there.)</label></p>
    <p><label><INPUT type=checkbox name=run_psh id=run_psh disabled>
		Use parallel shell (psh) command instead of xdsh.  When this option is chosen, some of the options below (associated with xdsh) are disabled.</label></p>

      <h3>Options:</h3>
    <TABLE id=inner_table cellspacing=0 cellpadding=5>
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
</table>

		<h3>Tips:</h3>
		<UL>
		  <LI>See the <A href="<?php echo getDocURL('manpage','xdsh.1'); ?>">xdsh man page</A> for more information about this command.</LI>
		</UL>
</FORM>
<script type='text/javascript'>dshReady();</script>

<?php
if (!isset($_REQUEST['intab'])) {
	echo "<div>\n";
	insertFooter();
}
?>
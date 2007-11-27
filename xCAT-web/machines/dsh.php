<?php
/*------------------------------------------------------------------------------
  Produce the page for running commands on the nodes of the cluster
------------------------------------------------------------------------------*/
$TOPDIR = '..';
$expire_time = gmmktime(0, 0, 0, 1, 1, 2038);
setcookie("history", "date;hello.sh", $expire_time);

require_once "$TOPDIR/lib/functions.php";
require_once("$TOPDIR/lib/XCAT/XCATCommand/XCATCommandRunner.class.php");

insertHeader('Run Commands on Nodes', array('themes/default.css'),
			array('javascripts/prototype.js', 'javascripts/effect.js', 'javascripts/window.js'),
			array('machines','dsh'));

?>
<div id=content>
<FORM NAME="dsh_options" onsubmit="checkEmpty();">
<input type="hidden" id="nodename" value=<?php echo @$_REQUEST["node"] ?> >
<TABLE class="inner_table" cellspacing=0 cellpadding=5>
  <TBODY>
  	<TR>
  	  <TD colspan="3">
		<?php if (@$_REQUEST["node"] == ""){ ?>
  	  	<font class="BlueBack">Run Command on Group</font>
  	  	<SELECT name=nodegrps id=nodegrpsCboBox class=middle>
  	  	<OPTION value="">Choose ...</OPTION>
  	  	<?php
  	  	$nodegroups = getGroups();
		foreach ($nodegroups as $group) {
				//if($group == $currentGroup) { $selected = 'selected'; } else { $selected = ''; }
				echo "<OPTION value='$group' $selected>$group</OPTION>\n";
		}
		?>
   		</SELECT>

   		<?php }else{ ?>
   		<font class="BlueBack">Run Command on Node:</font>
   		<SELECT name=nodegrps id=nodegrpsCboBox class=middle>
  	  	<OPTION value="">Choose ...</OPTION>
  	  	<?php
  	  	$nodes = getNodes(NULL, NULL);
		foreach ($nodes as $n) {
				$nodename = $n['hostname'];
				//if($nodename == $currentGroup) { $selected = 'selected'; } else { $selected = ''; }
				echo "<OPTION value='$nodename' $selected>$nodename</OPTION>\n";
		}
		?>
   		</SELECT>
   		<?php echo @$_REQUEST["node"];  } ?>
  	  </TD>
  	</TR>
	<TR>
	  <TD colspan="3">
		<P>Select a previous command from the history, or enter the command and options
		below. &nbsp;Then click on Run Cmd.</P>

	  </TD>
	</TR>
    <TR>
      <TD colspan="3"><font class="BlueBack">Command History: </font>
      <SELECT name="history" onChange="_setvars();" class="middle">
      <OPTION value="">Choose ...</OPTION>
      <?php
		$string = @$_COOKIE["history"];
		echo $token = strtok($string, ';');
		echo "<option value=\"" . $token . "\">" . $token . "</option>";

		while (FALSE !== ($token = strtok(';'))) {
   			echo "<option value=\"" . $token . "\">" . $token . "</option>";
		}
	 ?>
     </SELECT>
 	  &nbsp; &nbsp;Selecting one of these commands will fill in the fields below.
 	  </TD>
    </TR>
    <TR>
      <TD colspan="3"><div id="commandResult"></div></TD>
    </TR>
    <TR>
      <TD colspan="3"><p>
		<INPUT type="button" id="runCmdButton_top" name="runCmdButton_top" value="Run Cmd" class=middle ></p>
      </TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD colspan="3"><font class="BlueBack">Command:</font>&nbsp;
      <INPUT size="80" type="text" name="command" id="commandQuery" class="middle"></TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD colspan="3" nowrap><INPUT type="checkbox" name="copy_script" id="copyChkBox">
		Copy command to nodes &nbsp;(The command specified above will 1st be copied
      	to /tmp on the nodes and executed from there.)</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD colspan="3" nowrap><INPUT type="checkbox" name="run_psh" id="pshChkBox">
		Use parallel shell (psh) command</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD colspan="3" class="BlueBack"><B>Options:</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap><INPUT type="checkbox" name="serial" id="serialChkBox" checked>Streaming mode</TD>
      <TD width="500">Specifies that output is returned as it becomes available from each target, instead of waiting for the command_list to be completed on a target before returning output.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap><INPUT type="checkbox" name="verify" id="verifyChkBox">Verify</TD>
      <TD width="500">Verifies that nodes are responding before sending the command to them.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap><INPUT type="checkbox" name="collapse" id="collapseChkBox">Collaspe Identical Output</TD>
      <TD width="500">Automatically pipe the dsh output into dshbak which will only display output once for all the nodes that display identical output.  See the dshbak man page for more info.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap>Fanout:<INPUT type="text" name="fanout" id="fanoutTxtBox"></TD>
      <TD width="500">The maximum number of nodes the command should be run on concurrently. When the command finishes on 1 of the nodes, it will be started on an additional node (the default is 64).</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap>UserID:<INPUT type="text" name="userID" id="userIDTxtBox"></TD>
      <TD width="500">The user id to use to run the command on the nodes.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap>Remote Shell:<INPUT type="text" name="rshell" id="rshellTxtBox"></TD>
      <TD width="500">The remote shell program to use to run the command on the nodes, for example /usr/bin/ssh. (The default is stored by the csmconfig command or DSH_REMOTE_CMD enviroment variable).</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap>Shell Options:<INPUT type="txt" name="shell_opt" id="shell_optTxtBox"></TD>
      <TD width="500">Options to pass to the remote shell being used.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap><INPUT type="checkbox" name="monitor" id="monitorChkBox">Monitor</TD>
      <TD width="500">Prints the results of monitoring for each node in the form of the starting and completion messages for each node.</TD>
    </TR>
    <TR bgcolor="CCCCCC">
      <TD width="37"></TD>
      <TD width="210" valign="top" nowrap><INPUT type="checkbox" name="ret_code" id="ret_codeChkBox">Code Return</TD>
      <TD width="500">Prints the return code of the last command that was run remotely. The return code is appended at the end of the output for each node.</TD>
    </TR>
    <TR>
      <TD colspan="3">
		<INPUT type="button" id="runCmdButton_bottom" name="runCmdButton_bottom" value="Run Cmd" class=middle >

      </TD>
    </TR>
    <TR><TD colspan="3">
		<font class="BlueBack">Tips:</font>
		<UL>
		  <LI>See&nbsp;the <A href="$::CSMDIR/doc.cgi?book=cmdref&section=dsh">psh man page</A> for more information about this command.</LI>
		</UL>
	</TD></TR>
  </TBODY>
</TABLE>
</FORM>
<div>
<script type="text/javascript" src="js_xcat/event.js"> </script>
<script type="text/javascript" src="js_xcat/ui.js"> </script>
</BODY>
</HTML>
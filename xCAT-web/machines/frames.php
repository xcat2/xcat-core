<?php
/* session_start(); */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
insertHeader('xCAT Frame Node List', NULL, NULL, array('machines','frames'));
if (isAIX()) { $aixDisabled = 'disabled'; }
?>

<SCRIPT language="JavaScript">
function _reloadMe(form)
{
var url = 'nodes.cgi?';
url += 'rack=' + (form.rack.checked?1:0);
url += '&group=' + form.nodegrps.value;
url += '&nodeRange=' + form.nodeRange.value;
window.location = url;
}

function setCookies(form)
{
var value = (form.rack.checked?1:0) + '&' + form.nodegrps.value + '&' + form.nodeRange.value;
setCookie('mainpage', value);
}

function setCookie(name, value)
{
value = escape(value);
value = value.replace(/\\+/g, '%2B'); // The un_urlize() function in webmin works slightly differently than javascript escape()
document.cookie = name + '=' + value + ';expires=' + (new Date("December 31, 2023")).toGMTString();
}

function selectAll(element, rack)
{
var sel = element.checked;
if (rack) {
 for (var i=0; i < document.images.length; i++) {
  var image = document.images[i];
  if (image.src.search(/checked-box\\.gif\$/)>-1 && image.alt.search('^'+rack+'-')>-1) { imageCBClick(image,sel); }
 }
}
else {   // the form checkboxes
 var form = element.form;
 for(var i = 0; i < form.length; i++)
  {
   var e = form.elements[i];
   if (e.type == "checkbox" && e.name.search(/^node\\d/) > -1) { e.checked = sel; }
  }
}
}

function isNodeSelected(form)
{
if (document.paramForm.rack.checked) { return (form.Nodes.value.length>0 || form.rackNodes.value.length>0); }
// we only continue here if it is the non-rack display
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(/^node\\d/) > -1 && e.checked) { return true; }
 }
return false;
}

function numNodesSelected(form)
{
if (document.paramForm.rack.checked) {
 if (form.Nodes.value.length>0) { return 2; }  // just have to guess that the group or range has more than 1
 var val = form.rackNodes.value;
 var matches = val.match(/,/g);
 if (!matches) { return (val.length>0 ? 1 : 0); }
 else { return matches.length + 1; }
}
// we only continue here if it is the non-rack display
var j = 0;
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(/^node\\d/) > -1 && e.checked)
   {
    if (++j == 2) { return j; }
   }
 }
return j;
}

function CBClick(cb) { if (!cb.checked) { cb.form.selAllCheckbox.checked=false; } }

function imageCBClick(image, mode)
{
if (mode==1 || (mode==2 && (image.checked === undefined || !image.checked))) {
 image.src = 'images/checked-box.gif';
 image.checked = true;
} else {
 image.src = 'images/unchecked-box.gif';
 image.checked = false;
 var s=image.alt.split(/-/);
 var rackCB = document.nodesForm['selAll'+s[0]+'Checkbox'];
 rackCB.checked = false;
}
}

function gatherRackNodes(form)
{
 if (allSelected(form)) {
  if (document.paramForm.nodeRange.value.length > 0) { form.Nodes.value = document.paramForm.nodeRange.value; }
  else { form.Nodes.value = '+' + document.paramForm.nodegrps.value; }
  form.rackNodes.value='';
  return;
 }
 else { form.Nodes.value=''; }
 if (!document.paramForm.rack.checked) { form.rackNodes.value=''; return; }

 var nodes='';
 for (var i=0; i < document.images.length; i++) {
  var image = document.images[i];
  if (image.checked) { var s=image.alt.split(/-/); nodes += s[1] + ','; }
 }
 form.rackNodes.value = nodes.replace(/,\$/, '');
}

function allSelected(form)
{
if (document.paramForm.rack.checked) {
 for(var i = 0; i < form.length; i++)
  {
   var e = form.elements[i];
   if (e.type=="checkbox" && e.name.search(/^selAll\\d+Checkbox/)>-1 && !e.checked) { return false; }
  }
 return true;
}
else { return form.selAllCheckbox.checked; }   // non-rack display
}
</SCRIPT>

<div id=content>
<?php /* phpinfo(); */ ?>
<P align="center"><IMG src="images/csmlogo.gif" border="0"></P>
<H2>Node List on Management Server <?= $_SERVER["SERVER_NAME"] ?></H2>

<FORM name="paramForm" action="nodes.cgi" onsubmit="setCookies(this);">
<TABLE>
  <TBODY>
    <TR valign="middle">
      <TD>
      <P class="BlueBack"><B>Which Nodes:</B></P>
      </TD>
      <TD><B>&nbsp;Group: <SELECT name="nodegrps" size="1" onchange="setCookies(this.form);_reloadMe(this.form);" class="Middle">

<!--CSM
my $currentGroup = $::in{group};
if (!$currentGroup) { $currentGroup = 'AllNodes'; }

foreach my $group (@$nodegrp){
	my $selected = '';
	if($group eq "$currentGroup") { $selected = 'selected'; }
	print qq(<OPTION value='$group' $selected>$group</OPTION>\n);
}
CSM-->

      </SELECT> &nbsp;</B>or<B> &nbsp;Node Range: </B><INPUT size="20" type="text" name="nodeRange" value="$::in{nodeRange}" onchange="setCookies(this.form);_reloadMe(this.form);" class="Middle"></TD>
    </TR>
    <TR>
      <TD></TD>
      <TD>
<INPUT type="checkbox" name="rack" onclick="setCookies(this.form);_reloadMe(this.form);"> Show Nodes in Racks (have to first <A href="hwctrl/rack.cgi">set the physical location</A>)</TD>
    </TR>
  </TBODY>
</TABLE>
</FORM>
<!--
<SCRIPT language="JavaScript"> document.paramForm.rack.checked = ($rackChecked==1 ? true : false); </SCRIPT>
-->

<FORM name="nodesForm" action="nodes.cgi"
onsubmit="
gatherRackNodes(this);
if (this.nodesNeeded === undefined || this.nodesNeeded == 2) {    // need 1 or more nodes
 if (isNodeSelected(this)) { return true; }
 else { alert('Select one or more nodes before pressing an action button.');  return false; }
}
else if (this.nodesNeeded == 1) {                          // need exactly 1 node
 if (numNodesSelected(this) == 1) { return true; }
 else { alert('Exactly one node must be selected for this action.'); this.nodesNeeded=undefined; return false; }
}
else if (this.nodesNeeded == 0) { return true; }          // 0 or more nodes is ok
else { return true; }
">
<TABLE>
<TBODY>
    <TR>
      <TD><P class="BlueBack"><B>Node<BR>Actions:</B></P></TD>
      <TD>
      <TABLE cellpadding=0 cellspacing=2>
        <TBODY>
          <TR><TD nowrap>
<INPUT type=submit name=propButton value="Attributes" class=but>
<INPUT type=submit name=defineButton value="Define Like" class=but>
<INPUT type=submit name=createGroupButton value="Create Group" class=but>
<INPUT type=submit name=pingNodesButton value="Ping" class=but>
<INPUT type=submit name=updateButton value="Updatenode" class=but>
<INPUT type=submit name=runcmdButton value="Run Cmd" class=but>
<INPUT type=submit name=copyFilesButton value="Copy Files" class=but>
          </TD></TR>
        </TBODY>
      </TABLE>
      <TABLE cellpadding=0 cellspacing=2>
        <TBODY>
          <TR><TD nowrap>
<INPUT type=submit name=softMaintButton value="Soft Maint" class=but onclick="this.form.nodesNeeded=1;">
<INPUT type=submit name=hwctrlButton value="HW Ctrl" class=but>
<INPUT type=submit name=rsaButton value="RSA/MM/FSP" class=but onclick="this.form.nodesNeeded=1;">
<INPUT type=submit name=installButton value="Install" class=but>
<INPUT type=submit name=perfmonButton value="Perf Mon" class=but>
<INPUT type=submit name=webminButton value="Webmin" class=but onclick="this.form.nodesNeeded=1;">
<INPUT type=submit name=diagButton value="Diagnose" class=but onclick="this.form.nodesNeeded=1;">
<INPUT type=submit name=removeButton value="Remove" class=but>
          </TD></TR>
        </TBODY>
      </TABLE>
</TD>
    </TR>
    <TR>
      <TD colspan="2" height="5"></TD>
    </TR>
    <TR valign="top">
      <TD colspan="2" align="center">
<!--CSM if (!($rackChecked==1)) { -->
<?php
echo "<TABLE cellpadding=0><TBODY align=center valign=middle><TR valign=bottom class=BlueBack>\n";
echo "<TD align=left><INPUT type=checkbox name=selAllCheckbox onclick='selectAll(this,0)'><FONT size='-2'>Select All</FONT> &nbsp; <B>Name</B></TD>\n";
echo "<TD><B>HW Type</B></TD><TD><B>OS</B></TD><TD><B>Mode</B></TD><TD><B>Status</B></TD><TD><B>HW Ctrl Pt</B></TD><TD><B>Comment</B></TD></TR>\n";
$index =0;
?>
<!--CSM
foreach my $na (@$nodeAttrs)
{
  $index++;

  if ($index > $::config{MaxNodesDisplayed})
   {
    print qq(<TR><TD colspan=7 align=center><I>Note: Number of nodes to be displayed exceeds the maximum of $::config{MaxNodesDisplayed} specified on the <A href="/config.cgi?csm" target=_parent>Module Config page</A>.  To see the rest of the nodes, specify a node range or node group at the top of this page, or change the maximum value.</I></TD></TR>\n);
    last;
   }

  my ($hostname, $type, $osname, $distro, $version, $mode, $status, $conport, $hcp, $nodeid, $pmethod, $location, $comment) = split(/:\|:/, $na);
  print "<TR bgcolor='#d8dff1'><TD align=left nowrap><INPUT type='checkbox' name='node$index' value='$hostname' onclick='CBClick(this)'><A href='properties.cgi?nodes=$hostname'>$hostname</A></TD>\n";


  my $image = GuiUtils->getHWTypeImage($type, $pmethod);
  my $alt = $type;
  print qq(<TD><IMG src="images/$image" alt="$alt" title="$alt" border=0></TD>\n);


  if ($osname=~/aix/i) { $image = 'aix-s.gif'; $alt = 'AIX'; }
  elsif ($distro=~/redhat/i) { $image = 'redhat-s.gif'; $alt = 'RedHat'; }
  elsif ($distro=~/suse|sles/i) { $image = 'suse-s.gif'; $alt = 'SuSE/SLES'; }
  else { $image = '';  $alt = 'Unknown';}
  if (length($image)) { print qq(<TD nowrap><IMG src="images/$image" alt="$alt" title="$alt" border=0 align=top> $version</TD>\n); }
  else { print "<TD>$osname $distro $version</TD>\n"; }

  print "<TD>$mode</TD>\n";

  if ($status == 1) { $image = 'green-ball-m.gif';  $alt = 'On'; }
  elsif ($status == 127 && $mode eq 'PreManaged') { $image = 'blue-ball-m.gif';  $alt = 'Unconfigured'; }
  elsif ($status == 127) { $image = 'yellow-ball-m.gif';  $alt = 'Unknown'; }
  else { $image = 'red-ball-m.gif';  $alt = 'Off'; }
  print qq(<TD><IMG src="images/$image" alt="$alt" title="$alt" border=0></TD>\n);

  print "<TD>$hcp</TD>\n";

  print "<TD>$comment</TD></TR>\n";
} -->
<?= "</TBODY></TABLE>\n" ?>
<!--CSM
}  # not rack

else {   # show nodes in racks

print qq(<TABLE><TBODY valign=bottom><TR>\n);
# xSeries frames are 78.7in H x 23.6in W (3.3 ratio).  The server enclosure area is approx 71.4 x 19 (3.75 ratio).  Each U is approx 1.725

my $bord=0;
my $index=0;
for (my $fnum=1; $fnum<scalar(@frames); $fnum++) {
 my $frame = $frames[$fnum];
 if (!defined($frame)) { next; }  # no nodes in this frame
 print qq(<TD><INPUT type=checkbox name=selAll${fnum}Checkbox onclick='selectAll(this,$fnum)'><B> Rack $fnum</B>\n);
 print qq(<TABLE bgcolor="#303030" cellpadding=0 cellspacing=2><TBODY><TR><TD width=1 height=$bord></TD><TD></TD><TD width=1 height=$bord></TD></TR>\n);
 for (my $i=1; $i<=42;)
  {
  my $u = $$frame[$i];
  if (defined($u))
   {
   my ($hostname, $image, $alt, $size) = @$u;
   if (ref($image)) {    # this a bladecenter chassis
    my $chassis = $image;   # this is really a ref to an array of blades
    print qq(<TR><TD></TD><TD><TABLE bgcolor="#303030" cellpadding=0 cellspacing=1><TBODY><TR>\n);
    for (my $j=1; $j<=14; $j++) {
     my $b = $$chassis[$j];
     if (defined($b)) {
      my ($h, $im, $a) = @$b;
      $index++;
      print qq(<TD><IMG src='images/unchecked-box.gif' alt='$fnum-$h' title='$fnum-$h' border=0 onclick='imageCBClick(this,2);'><BR>);
      print qq(<IMG src="images/$im" alt="$a" title="$a" border=0></TD>\n);
     }
     else { print qq(<TD bgcolor="#999999" height=25 width=12></TD>\n); }  # empty blade slot
    }
    print qq(</TR></TBODY></TABLE></TD></TR>\n);
   }
   else {   # this is regular rack mounted node
    $index++;
    print qq(<TR><TD></TD><TD><IMG src='images/unchecked-box.gif' alt='$fnum-$hostname' title='$fnum-$hostname' border=0 align=middle onclick='imageCBClick(this,2);'>);
    print qq(<IMG src="images/$image" alt="$alt" title="$alt" border=0 align=middle></TD></TR>\n);
   }
   $i += $size;
   }
  else { print qq(<TR><TD></TD><TD bgcolor="#999999" height=5 width=50></TD></TR>\n); $i++; }   # empty slot
  }
 print qq(<TR><TD height=$bord></TD></TR></TBODY></TABLE></TD>\n);
}

print qq(</TR></TBODY></TABLE>\n);
}   # rack
CSM-->
 </TD>
    </TR>
  </TBODY>
</TABLE>
<INPUT type=hidden name=rackNodes value=''>
<INPUT type=hidden name=Nodes value=''>
</FORM>
<!--
<SCRIPT language="JavaScript">
if ($AIXdisable) {
 document.nodesForm.softMaintButton.disabled = true;
 document.nodesForm.rsaButton.disabled = true;
 document.nodesForm.installButton.disabled = true;
}
</SCRIPT>
-->
      <H4 class="BlueBack">Tips:</H4>
      <UL>
        <LI>Select 1 or more nodes &amp; click on an&nbsp;action button. &nbsp;Or choose
  1 of the main tasks on the left. &nbsp;The&nbsp;<A href="/help.cgi/csm/intro" target="_blank">Help&nbsp;link</A>&nbsp;at&nbsp;the&nbsp;top&nbsp;left&nbsp;really&nbsp;does&nbsp;help.&nbsp; It describes what all these buttons do.
        <LI>The Status colors: &nbsp;<FONT color="#00cc00">green</FONT>=reachable, <FONT color="#ff0000">red</FONT>=not reachable, <FONT color="#cccc00">yellow</FONT>=unknown/error, <FONT color="#0000ff">blue</FONT>=node not managed.
        <LI>If too many nodes are displayed, use the Group or Node Range selections
        to focus what is displayed.
        <LI>The <A href="/config.cgi?csm" target="_parent">Console/Settings link</A> at the top left is the way to set preferences. &nbsp;There is a verbose
        option there to have this interface display the commands it is running.
        <LI>If you are running this over a phone line, we recommend using the <A href="../webmin/change_theme.cgi?theme=">Old Webmin theme</A> (which is now the default) for faster loading. &nbsp;Of course, the <A href="../webmin/change_theme.cgi?theme=mscstyle3">MSC Linux theme</A> looks nicer. &nbsp;(If you change the theme, you will have to navigate
        back to this page in the Cluster category.)
        <LI>Did you know you can run as many browser windows with this interface as
        you want? &nbsp;This can be handy to view information from multiple pages&nbsp;of&nbsp;this&nbsp;interface
        at the same time.
      </UL>
      <P align="center"><FONT size="-1"><B>CSM Version:</B> $rpmVersions{'csm.server'} &nbsp; &nbsp; &nbsp; <B>CSM Web Interface Version:</B>&nbsp;$rpmVersions{'xcsm.web'}</FONT></P>
</div>
</body>
</HTML>

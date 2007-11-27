<?php

// Allow the user to set preferences for this web interface

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Suggestions', NULL, NULL, array('support','suggest'));
?>

<h1>Send Sugestions to the CSM Development Team</h1>

<p>Suggestions, bug reports, bug fixes, etc., are always welcome. Please post them to the
<A href="http://xcat.org/mailman/listinfo/xcat-user" >xCAT mailing list</A>.
Contributions are also welcome, such as minor new features, better
images, or even whole new pages.
See <a href="https://sourceforge.net/projects/xcat">xCAT on SourceForge</a>. Thanks!</p>

<h3>Todo List</h3>

<p>The following items are already on our todo list, in
approximately priority order:</p>

<ul>
  <li>Update the spec file for this web interface to have all the necessary post installation scripts.</li>
  <li>One button update of this web interface from the internet.</li>
  <li>Restructure the files in lib/XCAT and js_xcat to make them simpler.</li>
  <li>Have the task pane save the current task in the cookie and have each page set the current task.</li>
  <li>Do frame view and rack layout pages.</li>
  <li>Do several of the buttons within the machines views:
  <ul>
    <li>Attributes</li>
    <li>Ping</li>
    <li>Run Cmds</li>
    <li>Copy Files</li>
    <li>Create Group</li>
    <li>Diagnose</li>
  </ul>
  </li>
  <li>Do RMC configuration pages</li>
  <li>Do Cluster Settings (site table) page</li>
  <li>Start set up cluster wizard page.</li>
  <li>Do a summary page that lists # of bad nodes, # of jobs, etc.</li>
</ul>

<h3>Known Defects and Limitations</h3>

<ul>
  <li>to be filled in...</li>
</ul>

<p>The <b>Change Log</b> describing recent enhancements is in the xcat-web spec file</a>.</p>
</body>
</html>

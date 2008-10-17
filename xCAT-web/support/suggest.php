<?php

// Tell users how to request enhancements

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Suggestions', NULL, NULL, array('support','suggest'));
?>

<h1>Send Sugestions to the xCAT Development Team</h1>

<p>Suggestions, bug reports, bug fixes, etc., are always welcome. Please post them to the
<A href="http://xcat.org/mailman/listinfo/xcat-user" >xCAT mailing list</A>.
Contributions are also welcome, such as minor new features, better
images, whole new pages, or enhancements to base xCAT.
See the <a href="http://xcat.wiki.sourceforge.net/xCAT+2+Contribution+Guildelines">xCAT contribution guidelines</a>
for more information.</p>

<p>To see what is already on our todo list for this web interface, or to request a new feature,
go to the <a href="http://xcat.wiki.sourceforge.net/Web+Interface+Wish+List">Web Interface Wish List</a>.</p>

<?php insertFooter(); ?>
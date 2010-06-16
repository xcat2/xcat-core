<div id="siteMap">
	<a href="config.php">Tables</a> > site
</div>
<div id="tabTable">
	<table>
		<tr><td class='editme'>xcatport</td><td class='editme'>3001</td></tr>
		<tr><td class='editme'>iscsidir</td><td class='editme'>/install/iscsi</td></tr>
		<tr><td class='editme'>tftpdir</td><td class='editme'>/tftpboot</td></tr>
		<tr><td class='editme'>nfsdir</td><td class='editme'>/install</td></tr>
	</table>
</div>

<script type="text/javascript">
	//jQuery(document).ready(function() {
	makeEditable('<?php echo $tab ?>', '.editme');

	// Set up global vars to pass to the newrow button
	document.linenum = <?php echo $line ?>;
	document.ooe = <?php echo $ooe ?>;

	// Set actions for buttons
	$("#reset").click(function(){
		//alert('You sure you want to discard changes?');
		$('#middlepane').load("edittab.php?tab=<?php echo $tab ?>&kill=1");
		});
	$("#newrow").click(function(){
		var newrow = formRow(document.linenum, <?php echo $tableWidth ?>, document.ooe);
		document.linenum++;
		document.ooe = 1 - document.ooe;
		$('#tabTable').append($(newrow));
		makeEditable('<?php echo $tab ?>', '.editme2', '.Ximg2', '.Xlink2');
	});
	$("#saveit").click(function(){
		$('#middlepane').load("edittab.php?tab=<?php echo $tab ?>&save=1", {
		indicator : "<img src='../images/indicator.gif'>",
		});
	});
	//});
</script>




// Javascript functions needed by the db page.

// Make this class of elements editable
function makeEditable(table, cellclass, imgclass, linkclass) {
	// Make all the cells editable
	//todo: figure out how to make the tab key commit the current cell and edit the next
	$(cellclass).editable('change.php?tab=' + table, {
		indicator : "<img src='../images/indicator.gif'>",
		type      : 'text',
		tooltip		: 'Click to edit...',
		style		: 'inherit',
		cssclass	: 'inherit',
		placeholder	: ''
	//	callback	: function(value,settings) { alert(dump(settings)); }
	});

	// Set up rollover and action for red x to delete row
	$(imgclass).hover(function() { $(this).attr('src','../images/red-x2.gif'); },
		function() { $(this).attr('src','../images/red-x2-light.gif'); }
	);
	$(linkclass).click(function() {
		var tr = $(this).parent().parent();
		var rowid = tr.attr('id');
		var match = rowid.match(/\d+/);
		$.get('change.php?tab=' + table + '&delrow=' + match[0]);
		tr.remove();
	});
}


// Form a table row to add to the table
function formRow(linenum, numCells, ooe) {
var newrow = '<tr class=ListLine' + ooe + ' id=row' + linenum + '><td class=Xcell><a class=Xlink2 title="Delete row"><img class=Ximg2 src=../images/red-x2-light.gif></a></td>';
for (var i=1; i<=numCells; i++) {
	var val = '';
	if (i == 1)  { val = 'x'; }
	newrow += '<td class=editme2 id="' + linenum + '-' + i + '">' + val + '</td>';
}
newrow += '</tr>';
return newrow;
}


// Load edittab.php, specifying this table as a param
function loadTable(table) {
var url = 'edittab.php?tab=' + table;
$('#middlepane').load(url);
}


// Associate a click event with each table link to get its url (which is
// the table name) and load edittab.php with that table name.
function bindTableLinks() {
$('#tableNames A').click(function(e) {
	var tableName = this.hash.substr(1);		// strip off the leading # in the hash string
	loadTable(tableName);
	return false;
	});
}
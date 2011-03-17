/*
*   Globle variable
*
*/
var XcatmonTableId="XcatMonsettingTable";
var dataTables=new Object();

/*
*	set datatable
*
*/
function setDatatable(id,obj){
	dataTables[id]=obj;
}
/*
* get datatable from the given id
*
*
*/
function getDatatable(id){
	return dataTables[id];
}
/*
*	
*
*/

function loadXcatMon(){
	//find the xcat mon tab
	var xcatMonTab = $('#xcatmon');
	
	xcatMonTab.append("<div id= xcatmonTable></div>");
	// show the content of the table monsetting
	$.ajax({
		url:'lib/cmd.php',
		dataType: 'json',
		data:{
			cmd : 'tabdump',
			tgt :'',
			args : 'monsetting',
			msg : ''
		},
		success: loadXcatMonSetting
	});	
}
function loadXcatMonSetting(data){
	
	var apps;// contain the xcatmon apps config
	var rsp=data.rsp;	
	var apps_flag=0;// Is the apps is stored?
	var ping; // contain the xcatmon ping-interval setting
	var ping_flag=0;


	//create a infoBar	
	var infoBar=createInfoBar('Click on a cell to edit,Click outside the table to write to the cell.<br>Once you finish the xCATmon config.click on Apply.');
	$('#xcatmonTable').append(infoBar);
	
	//create xcatmonTable
	var XcatmonTable= new DataTable(XcatmonTableId);
	
	//create Datatable
	var dTable;
	
	// create the xcatmonTable header	
	var header=rsp[0].split(",");	
	header.splice(3,2);
	header.splice(0,1);
	header[0]="apps name";
	header[1]="configure";
	header.push('<input type="checkbox" onclick="selectAllCheckbox(event,$(this))">');

	header.unshift('');
	XcatmonTable.init(header);//create the table header


	// create container of original table contents
	var origCont= new Array();
	origCont[0]=header;// table header

	//create contariner for new contents use for update the monsetting table
	var newCont =new Object();
	newCont[0]=rsp[0].split(",");// table header	
	// create container for other monsetting lines not xcatmon
	var otherCont =new Array();
	




	$('#xcatmonTable').append(XcatmonTable.object());// add table object
	var m=1;// the count for origCont
	var n=0;
	for( var i=1;i<rsp.length;i++){ // get the apps and the ping-interval configure
		var pos=rsp[i].indexOf("xcatmon");// only check the xcatmon setting
		if(pos ==1){
			// get the useful info and add it to the page.
			
			if((rsp[i].indexOf("apps")== -1 )&&(rsp[i].indexOf("ping")== -1)){
				var cols=rsp[i].split(',');

				// pair the semicolon of the content
				for(var j=0;j<cols.length;j++){
					if(cols[j].count('"')%2==1){
						while(cols[j].count('"')%2==1){
						cols[j]=cols[j]+","+cols[j+1];
						cols.splice(j+1,1);
						}
					}
				cols[j]=cols[j].replace(new RegExp('"','g'),'');	
				}
				// remove the commend disable
				cols.splice(3,2);
				// remove the xcatmon
				cols.splice(0,1);
				
				cols.push('<input type="checkbox" name="'+cols[0]+'" title="Click this checkbox will add/remove the app from the configure apps value." />');
				cols.unshift('<span class="ui-icon ui-icon-close" onclick="deleteRow1(this)"></span>');
				//add teh column tho the table.
				XcatmonTable.add(cols);
				
				origCont[m++]=cols;
			}else{

				if(!apps_flag){//check the apps setting
					if(rsp[i].indexOf("apps") > -1){// check for  is  apps or not
						apps=rsp[i].split(',');// 
					
						for(var j=0;j<apps.length;j++){// pair the semicolon
							if(apps[j].count('"')%2==1){
								while(apps[j].count('"')%2==1){
								apps[j]=apps[j]+","+apps[j+1];
								apps.splice(j+1,1);
								}
							}
							apps[j]=apps[j].replace(new RegExp('"','g'),'');
						}
					
						apps_flag=1;// set the flag to 1 to avoid this subroute
					}
				}
				// get into the ping setting subroute
				if(!ping_flag){
					//check the ping-interval config
					if(rsp[i].indexOf("ping-interval")> -1){
						ping=rsp[i].split(',');
						// pair the semicolon
						for(var j=0;j<ping.length;j++){

							if(ping[j].count('"')%2 == 1){
								while(ping[j].count('"')%2 == 1){
									ping[j]=ping[j]+","+ping[j+1];
									ping.splice(j+1,1);
								}

							}
							ping[j]=ping[j].replace((new RegExp('"','g')),'');
						}
						ping_flag=1;
					}
	

				}

			}			

		}else if(pos !=1 ){
			// the other monitor in the monsetting table
			var otherCols=rsp[i].split(',');
			for(var k=0;k<otherCols.length;k++){
				if(otherCols[k].count('"')%2==1){
					while(otherCols[k].count('"')%2==1){
						otherCols[k]=otherCols[k]+","+otherCols[k+1];
						otherCols.splice(k+1,1);
					}
				}
				otherCols[k]=otherCols[k].replace(new RegExp('"','g'),'');
			}
			//add the rows to the otherCont.
			otherCont[n++]=otherCols;

		}
	}
	// if the apps is not in the monsetting table.Then create the default apps row.
	// When saving the changes,add the row to the table.
	if(!apps_flag){
		apps=rsp[0].split(',');
		apps[0]="xcatmon";
		apps[1]="apps";
		apps[2]="";
		apps[3]="";
		apps[4]="";
		}

	// If the ping-interval is not in the monsetting table.Then create the default ping-interval row.
	//When saving the changes,add the row to the table.
	if(!ping_flag){
		ping=rsp[0].split(',');
		ping[0]="xcatmon";
		ping[1]="ping-interval";
		// the default ping-interval setting is 5
		ping[2]="5";
		ping[3]="";
		ping[4]="";
	}

	// set the checkbox to be true according to the apps

	var checked=apps[2].split(',');
	for(var i=0;i<checked.length;i++){
		// set the selcet checkbox to  true
		$("input:checkbox[name="+checked[i]+"]").attr('checked',true);
		for(var j =0;j<origCont.length;j++){
			// set the origCont's checkbox to true
			if(origCont[j][1]==checked[i]){
				origCont[j].splice(3,1);
	
				origCont[j].push('<input type="checkbox" name="'+origCont[j][1]+'" title="Click this checkbox will add/remove the app from the configure apps value." checked=true/>');
			}
		}

	}
	$(":checkbox").tooltip();
/*
	$(':checkbox').hover(
		function(){
			$(this).append($("<span>***</span>"));
		},
		function(){
			$(this).find("span:last").remove();
		}
	);

*/

	//make the table editable

	$('#'+XcatmonTableId+' td:not(td:nth-child(1),td:last-child)').editable(

		function(value,settings){

		var colPos=this.cellIndex;
		var rowPos=dTable.fnGetPosition(this.parentNode);
		
		dTable.fnUpdate(value,rowPos,colPos);
		
		return (value);
		},{
		onblur : 'submit',
		type : 'textarea',
		placeholder: ' ',
		height : '30px'
		}

	);
	//save the datatable 
	dTable=$('#'+XcatmonTableId).dataTable();
	// set the datatable to the global variables datatables
	setDatatable(XcatmonTableId,dTable);
	

	//create button bar
	var addBar = $('<div align="center"></div>');
	$('#xcatmon').append(addBar);
	// create the button add row
	var addRowBtn=createButton('Add row');
	// add the button to the page
	addBar.append(addRowBtn);
	// create the button apply
	var ApplyBtn=createButton('Apply');
	// add the apply button to the page
	addBar.append(ApplyBtn);
	// create the button Cancel
	var CancelBtn=createButton('Cancel');
	// add the cancel to the page
	addBar.append(CancelBtn);
	
	// button click function

	//create a empty row
	addRowBtn.bind('click',function(event){
		// create the container of the new row
		var row = new Array();
	
		// add the delete button to the row
		row.push('<span class="ui-icon ui-icon-close" onclick="deleteRow1(this)"></span>');
		// add the xcatmon
		// add the contain of the setting
		for(var i =0;i<header.length-2;i++){
			row.push('');
		}
		// add the checkbox
		row.push('<input type="checkbox" name="'+row[2]+'" title="Click this checkbox will add/remove the app from the configure apps value."/>');
		// get the datatable of the table
		var dTable=getDatatable(XcatmonTableId);
		// add  the new row to the datatable
		dTable.fnAddData(row);
	
		// make the datatable editable
		$(":checkbox[title]").tooltip();
		$('#'+XcatmonTableId+' td:not(td:nth-child(1),td:last-child)').editable(
			function(value,settings){
			var colPos=this.cellIndex;
			var rowPos=dTable.fnGetPosition(this.parentNode);
		
			dTable.fnUpdate(value,rowPos,colPos);
		
			return (value);
			},{
			onblur : 'submit',
			type : 'textarea',
			placeholder: ' ',
			height : '30px'
			}

		);

	});


/*
*		apply button
*
*
*
*	The Apply button is used to store the contain of the table in the page to the monsetting table 
*	on the MN.
*
*/
	ApplyBtn.bind('click',function(event){
		// get the datatable of the page
		var dTable=getDatatable(XcatmonTableId);
		// get the rows of the datatable
		var dRows=dTable.fnGetNodes();	
		var count=0;
		// create the new container of the apps' value.
		var appValue="";
		var tableName="monsetting";
		var tmp;
		var tmp1;
		// get the contain of the rows 
		for (var i =0; i< dRows.length;i++){
			
			if(dRows[i]){
				// get the columns fo the row
				var cols=dRows[i].childNodes;
				// create the container of the new column 
				var vals = new Array();

				for(var j=1;j<cols.length-1;j++){
					// get the value of every column(except the first and the last.why ? .ni dong de)
					var val=cols.item(j).firstChild.nodeValue;

					if(val == ' ' ){
						vals[j-1]='';	
					}else{
						vals[j-1]=val;
					}
				}
				// prepare another space for the array/
				var vals_orig=new Array();
				// copy the data from vals to vals_orig
				for(var p=0 ;p<2;p++){
						var val=vals[p];
						vals_orig[p]=val;	
					}

				vals.push("");
				vals.push("");
				vals.unshift("xcatmon");
				// stored the new column to the newCont
				newCont[i+1]=vals;


				// check the checkbox of the row and add different checkbox to the orignCont
				// for the cancle button
				if(cols.item(cols.length-1).firstChild.checked){
		vals_orig.push('<input type="checkbox" name="'+vals_orig[0]+'" title="Click this checkbox will add/remove the app from the configure apps value." checked=true/>');
				}else{
		vals_orig.push('<input type="checkbox" name="'+vals_orig[0]+'" title="Click this checkbox will add/remove the app from the configure apps value."/>');
				}	
				// push the delete button to the row
				vals_orig.unshift('<span class="ui-icon ui-icon-close" onclick="deleteRow1(this)"></span>');
				// add the row to the orignCont

				origCont[i+1]=vals_orig;
				//tmp1=origCont;
				//tmp=newCont;
				count=i+1;
				
				// check the checkbox fo everyrow for merging the appName to  the apps values
				if(cols.item(cols.length-1).firstChild.checked){
					// the new value for the apps.get the name fo every app.
					appValue=appValue.concat(cols.item(2).firstChild.nodeValue+",");
				}
			}
		}
		count++;
		// delete the last "," of the apps value
		appValue=appValue.substring(0,(appValue.length-1));
		apps[2]=appValue;

//		tmp =apps;
		
		// newCont add the apps row
		newCont[count++]=apps;
		// newCont add the ping-interval row
		newCont[count++]=ping;
		//tmp=otherCont;
		// add the other monitor setting of the mosetting
		for(var j=0;j<otherCont.length;j++){
			newCont[count++]=otherCont[j];
		}
		//tmp=otherCont.length;
		//tmp1=newCont;	
		setDatatable(XcatmonTableId,dTable);

		
		// pot the table name and the contain to the tabRestore.php
		$.ajax({
			type : 'POST',
			url : 'lib/tabRestore.php',
			dataType : 'json',
			data : {
				table : tableName,
				cont : newCont
			},
			success : function (data){
				alert('changes saved');
			}

		});

		// clear the newCont
		newCont=null;
		newCont= new Object();
		//just for tet			tmp=newCont;
		newCont[0]=rsp[0].split(",");
		


	}
	);





/*
*		undo button
*
*/
	CancelBtn.bind('click',function(event){
		
		// get the datatable of the page
		var dTable=getDatatable(XcatmonTableId);
		
		// clear the datatable
		dTable.fnClearTable();

		// add the contain of the origCont to the datatable
		for(var i=1;i<origCont.length;i++){
			dTable.fnAddData(origCont[i],true);
		}	

		$(":checkbox[title]").tooltip();
	$('#'+XcatmonTableId+' td:not(td:nth-child(1),td:last-child)').editable(
		function(value,settings){
		var colPos=this.cellIndex;
		var rowPos=dTable.fnGetPosition(this.parentNode);
		
		dTable.fnUpdate(value,rowPos,colPos);
		
		return (value);
		},{
		onblur : 'submit',
		type : 'textarea',
		placeholder: ' ',
		height : '30px'
		}
		
	);	

	}
	);



}

// delete a row from the table
function deleteRow1(obj){
	//var tableid=$(obj).parent().parent().parent().parent().attr('id');
	var dTable=getDatatable(XcatmonTableId);
	var rows=dTable.fnGetNodes();
	var tgtRow=$(obj).parent().parent().get(0);
	for (var i in rows){
		if(rows[i] == tgtRow){
			dTable.fnDeleteRow(i, null,true);
			break;
		}

	}



}
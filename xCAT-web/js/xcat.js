var zIndex = 1;
function addLoadEvent(func) {
	var oldonload = window.onload;
	if (typeof window.onload != 'function') {
		window.onload = func;
	} else {
		window.onload = function() {
			if (oldonload) {
				oldonload();
			}
			func;
		}
	}
}
	
	
var activeNode;

function startList() {
	if (document.getElementById('menubeans')) {
		navRoot = document.getElementById('menubeans');
		for (i = 0; i < navRoot.childNodes.length; i++) {
			node = navRoot.childNodes[i];
			if (node.nodeName == 'LI') {
				if (node.className == 'active') {
					activeNode = i;
				}
			}
		}
		for (i = 0; i < navRoot.childNodes.length; i++) {
			node = navRoot.childNodes[i];
			if (node.nodeName == 'LI') {
				node.onmouseover = function() {
					navRoot.childNodes[activeNode].className = '';
					this.className = 'active';
				}
  				node.onmouseout = function() {
					this.className = '';
					navRoot.childNodes[activeNode].className = 'active';
				}
				node.onmousedown = function() {
					navRoot.childNodes[activeNode].className = '';
					this.className = 'active';
					activeNode = this.id - 1;
				}
	
			}
		}
	}
}

var activeNN = '2-li-0';
function chActiveMenu(newk){
	// find active node
	//alert("value for AN" + activeNN);
	//alert("value for newk" + newk);
	/* set old one to nothing */
	document.getElementById(activeNN).className = '';
	/* set new one to active */
	document.getElementById(newk).className = 'active';
	activeNN = newk;
}
function resetForm(fobj){
	fobj.reset();
	closeTree();
}

function getFormVals(fobj) { 
	var str = ''; 
	var ft = ''; 
	var fv = ''; 
	var fn = ''; 
	var els = ''; 
	for(var i = 0;i < fobj.elements.length;i++) { 
		els = fobj.elements[i]; 
		ft = els.title; 
		fv = els.value; 
		fn = els.name; 
		switch(els.type) { 
			case "text": 
			case "hidden": 
			case "password": 
			case "textarea": 
			// is it a required field? 
			if(encodeURI(ft) == "required" && encodeURI(fv).length < 1) { 
			alert(fn + ' is a required field, please complete.');  
			els.focus();  
				return false;  
			}  
			str += fn + "=" + encodeURI(fv) + "&";  
			break;   
   
			case "checkbox":  
			case "radio":  
				if(els.checked) str += fn + "=" + encodeURI(fv) + "&";  
				break;      
   
			case "select-one":  
				str += fn + "=" +  
				els.options[els.selectedIndex].value + "&";  
				break;  
		} // switch  
	} // for  
	str = str.substr(0,(str.length - 1));  
	return str;  
}


function killChildren(domE){
	for(var i = 0; i<domE.childNodes.length; i++){
		domE.removeChild(domE.childNodes[i]);
	}
}


function getCmdWindow(){
	var d = '';
	var dob = '';
	d = document.getElementById('cmd');
	if(!d){
		d = winNewWin('Command Output');
		var foo = document.createElement('div');
		foo.id = 'cmd';
		foo.innerHTML = '&nbsp';
		d.appendChild(foo);
		d = foo;
	}else{
		killChildren(d);
	}
	return d;
}

function doForm(fobj){
	/* make a new place for our form to appear */
	var d = getCmdWindow();
	/* get all form data */
	var data = getFormVals(fobj);
	/* noew request it all */
	/* alert(data); */
	new Ajax.Updater(d, 'parse.php', 
		{method:'post',
		postBody: data,
		evalScripts: true
		});
	resetForm(fobj);
}

function newPane(turl, tobj, title, newk){
	var el = winNewWin(title);
	new Ajax.Updater(el, turl, 
		{evalScripts:true}); 
	chActiveMenu(newk);
}

function newBack(turl, tobj, title, newk){
	new Ajax.Updater(tobj, turl, 
		{evalScripts:true}); 
	chActiveMenu(newk);
}

function firstLoad(){
	var turl = 'xcattop.php';
	new Ajax.Updater('content', turl, 
		{evalScripts:true}); 
}

function newPane2(turl, tobj, title){
	var el = winNewWin(title);
	new Ajax.Updater(el, turl, 
		{evalScripts:true}); 
	
}


function getNodeStatus(divID){
	var id = 'grid' + divID;
	var el = document.getElementById(id);	
	new Ajax.Updater(el, 'pingNode.php?n=' + divID, {evalScripts: true});
}

function chNodeStatus(node, status){
	var id = 'grid' + node;
	var el = document.getElementById(id);
	el.className = status;
	el.innerHTML = node;
}







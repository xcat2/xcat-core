var winNum = 1;
var zIndex = -100;

function winNewWin(title){
	var dob;
	var d;
	dob = document.getElementById('content');
	
	d = document.createElement('div');
	d.className = 'block';
	var winid = 'window' + winNum;
	d.id = 'window' + winNum;
	d.style.zIndex = zIndex;
	zIndex++;
	d.appendChild(winNewTitleBar(title));
	var cont = winNewContent();
	d.appendChild(cont);
	dob.appendChild(d);
	new Draggable(winid, {handle: 'handle'});
	winNum++;
	/* return s the place to start writing */
	return cont;
}

function winNewTitleBar(title){
	var ti = document.createElement('h3');
	ti.className = 'handle';
	var winid = 'window' + winNum;
	var newHTML =  "<a class='block-close' ";
	newHTML += "alt='Close Window' ";
	newHTML += "onClick=\"winKill('" + winid + "')\">";
	newHTML += "<span>&nbsp;</span></a>"
	newHTML += "<a class='block-toggle' ";
	newHTML += "alt='Toggle Window' ";
	newHTML += "onClick=\"Effect.toggle('winContent";
	newHTML += winNum ;
	newHTML += "','slide')\">";
	newHTML += "<span>&nbsp;</span></a>";
	newHTML += title;
	ti.innerHTML = newHTML;
	return ti;
}

function winNewContent(){
	var doc = document.createElement('div');
	doc.className = 'blockContent';
	doc.id = 'winContent' + winNum ;
	return doc;
}

function winKill(wid){
        // Todo: make this random effects
	var w = document.getElementById(wid);
        Effect.Puff(w);
	w.parentNode.removeChild(w);
        // var killU = w.parentNode;
        // killU.removeChild(w);
}

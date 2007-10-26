


processHeader = function(head,ul) {


	/* make the head icon different */
	for (i=0; i < head.childNodes.length; i++ ) {
		if(head.childNodes[i].className = "nodeIcon"){
			head.childNodes[i].className = "nodeGroupIcon";
			break;
		}
	}
	/* add the plus and expandibility */	
	myBox = document.createElement('span');
	myBox.className = 'plus';
	myBox.innerHTML = "&nbsp;";
	myBox.onclick = function() {
			this.className = (this.className == 'plus') ? 'minus' : 'plus';
			this.parentNode.parentNode.className = (this.parentNode.parentNode.className=='open') ? 'closed' : 'open';
        	return false;
	}
	head.insertBefore(myBox, head.childNodes[0]);
	head.parentNode.className = 'closed';
}

processItem = function(li, lili){
	myN = document.createElement('span');
	myIcon = document.createElement('span');
	myIcon.innerHTML = "&nbsp";
	myCheck = document.createElement('span');
	myIcon.className = "nodeIcon";
	myCheck.className = "unchecked";
	myCheck.onclick = function (){
		this.className = (this.className=='checked') ? "unchecked" : "checked";
		//this.parentNode.
   		return false;
	}

	/* create form element */
	myInput = document.createElement('input');
	myInput.type = 'checkbox';
	myInput.id = 'input';
	myInput.name = 'nodes[]';
	myInput.value = lili.nodeValue;
	/* end create form element */
	li.insertBefore(myN, lili);
	li.removeChild(lili);
	// myCheck.appendChild(lili);
	// myInput.appendChild(lili);
	myN.appendChild(myIcon);
	// myN.appendChild(myCheck);
	myN.appendChild(myInput);
	myN.appendChild(lili);
	return myN;
}



processList = function(ul) {
	if (!ul.childNodes || ul.childNodes.length == 0) return;
	isFirst = '';
	isLast = '';
	tempNode = '';
	for (var i=0; i < ul.childNodes.length; i++ ) {
		li = ul.childNodes[i];
		if (li.nodeName == "LI") {
		var subUL = '';
		var head = '';
		for(j = 0; j < li.childNodes.length; j++) {
			lili = li.childNodes[j];
				switch (lili.nodeName) {
					case "#text": 
						myN = processItem(li, lili);
						head = myN;
						break;
					case "UL": 
						subUL = lili;
						processList(lili);
						break;
		    		default: 
						// other items may be a span.
						// alert("exception:" + lili.nodeName);
						break;
				}
			}
			if (subUL) {
				processHeader(head,subUL);
			} else {
				//alert('cl: ' + (ul.childNodes.length - 1));
				if(isFirst == ''){
					li.className = 'firstItem';
					isFirst = 1;
				}
				else {
					if(isLast == ''){
						li.className = "lastItem";
						tempNode = li;
						isLast = 1;
					}else{
						tempNode.className = "middleItem";
						li.className = "lastItem";
						tempNode = li;
					}
				}
			}
        }
    }
}

makeTree = function(el) {
	// see if we can create an element
	if (!document.createElement) return;
	ul = document.getElementById(el);
	if(!ul){
		return;
	}
	ul.className = "clickTree";
	processList(ul);
}

function closeTree(){
	var el = document.getElementsByClassName('minus');
	for(var i = 0; i< el.length; i++){
		el[i].className = 'plus';
		el[i].parentNode.parentNode.className = 'closed';
	}
}


rconsTerm = function(nodeName, height, width){
	var sid=nodeName;
	var keyBuf = [];
	var receivingFlag = false;
	var sendTimeout;
	var errorTimeout;
	var queryStable = 's=' + sid + '&w=' + height + '&h=' + width + '&c=1&k=';
	var maxDelay = 200;
	var firstFlag = true;
	
	var workingStatus;
	var termArea;
	var errorArea;
	
	var ie=0;
	if(window.ActiveXObject){
		ie=1;
	}
	
	rconsInit();
	//init 
	function rconsInit(){
		//create status, configure the css
		workingStatus = $('<span>.</span>');
		workingStatus.attr('class', 'off');
		
		//create the disconnect button
		var disconnectButton = $('<a class="off">Disconnect</a>');
		disconnectButton.bind('click', function(){
			window.close();
		});
		
		//create the control panel,  add to the rcons div
		var controlPanel = $('<pre class="stat"></pre>');
		$('#term').append(controlPanel);
		
		//create the error erea
		errorArea = $('<span></span>');
		
		//add all item to controlPanel
		controlPanel.append(workingStatus);
		controlPanel.append(disconnectButton);
		controlPanel.append(errorArea);
		
		//create the termArea
		termArea = $('<div></div>');
		$('#term').append(termArea);
		
		//bind keypress event
		document.onkeypress=rconsKeypress;
		document.onkeydown=rconsKeydown;
		window.onbeforeunload = function(){
			rconsDisconnect();
			alert("This rcons page is closed.");
		};
		
		rconsSend();
	}
	
	//close the connection
	function rconsDisconnect(){
		window.clearTimeout(sendTimeout);
		window.clearTimeout(errorTimeout);
		
		$.ajax({
			type : "POST",
			url : "lib/rcons.php",
			data : queryStable + '&q=1',
			dataType : 'json'
		});
	}

	//translate the key press
	function rconsKeypress(event){
		if (!event) var event=window.event;
		var kc;
		var k="";
		if (event.keyCode)
			kc=event.keyCode;
		if (event.which)
			kc=event.which;
		if (event.altKey) {
			if (kc>=65 && kc<=90)
				kc+=32;
			if (kc>=97 && kc<=122) {
				k=String.fromCharCode(27)+String.fromCharCode(kc);
			}
		} else if (event.ctrlKey) {
			if (kc>=65 && kc<=90) k=String.fromCharCode(kc-64); // Ctrl-A..Z
			else if (kc>=97 && kc<=122) k=String.fromCharCode(kc-96); // Ctrl-A..Z
			else if (kc==54)  k=String.fromCharCode(30); // Ctrl-^
			else if (kc==109) k=String.fromCharCode(31); // Ctrl-_
			else if (kc==219) k=String.fromCharCode(27); // Ctrl-[
			else if (kc==220) k=String.fromCharCode(28); // Ctrl-\
			else if (kc==221) k=String.fromCharCode(29); // Ctrl-]
			else if (kc==219) k=String.fromCharCode(29); // Ctrl-]
			else if (kc==219) k=String.fromCharCode(0);  // Ctrl-@
		} else if (event.which==0) {
			if (kc==9) k=String.fromCharCode(9);  // Tab
			else if (kc==8) k=String.fromCharCode(127);  // Backspace
			else if (kc==27) k=String.fromCharCode(27); // Escape
			else {
				if (kc==33) k="[5~";        // PgUp
				else if (kc==34) k="[6~";   // PgDn
				else if (kc==35) k="[4~";   // End
				else if (kc==36) k="[1~";   // Home
				else if (kc==37) k="[D";    // Left
				else if (kc==38) k="[A";    // Up
				else if (kc==39) k="[C";    // Right
				else if (kc==40) k="[B";    // Down
				else if (kc==45) k="[2~";   // Ins
				else if (kc==46) k="[3~";   // Del
				else if (kc==112) k="[[A";  // F1
				else if (kc==113) k="[[B";  // F2
				else if (kc==114) k="[[C";  // F3
				else if (kc==115) k="[[D";  // F4
				else if (kc==116) k="[[E";  // F5
				else if (kc==117) k="[17~"; // F6
				else if (kc==118) k="[18~"; // F7
				else if (kc==119) k="[19~"; // F8
				else if (kc==120) k="[20~"; // F9
				else if (kc==121) k="[21~"; // F10
				else if (kc==122) k="[23~"; // F11
				else if (kc==123) k="[24~"; // F12
				if (k.length) {
					k=String.fromCharCode(27)+k;
				}
			}
		} else {
			if (kc==8)
				k=String.fromCharCode(127);  // Backspace
			else
				k=String.fromCharCode(kc);
		}
		if(k.length) {
			if(k=="+") {
				rconsQueue("%2B");
			} else {
				rconsQueue(escape(k));
			}
		}
		event.cancelBubble=true;
		if (event.stopPropagation) event.stopPropagation();
		if (event.preventDefault)  event.preventDefault();
		return false;	
	}
	
	//translate the key press, same with rconsKeypress
	function rconsKeydown(event){
		if (!event) var event=window.event;
		if (ie) {
			o={9:1,8:1,27:1,33:1,34:1,35:1,36:1,37:1,38:1,39:1,40:1,45:1,46:1,112:1, 113:1,114:1,115:1,116:1,117:1,118:1,119:1,120:1,121:1,122:1,123:1};
			if (o[event.keyCode] || event.ctrlKey || event.altKey) {
				event.which=0;
				return keypress(event);
			}
		}
	}
	
	//send the command and request to server
	function rconsSend(){
		var keyPressList = '';
		var requireString = '';
		if(receivingFlag){
			return;
		}
		
		receivingFlag = true;
		workingStatus.attr('class', 'on');
		
		while(keyBuf.length > 0){
			keyPressList += keyBuf.pop(); 
		}
		
		if (firstFlag){
			requireString = queryStable + keyPressList + '&f=1';
			firstFlag = false;
		} else{
			requireString = queryStable + keyPressList;
		}
		
		$.ajax({
			type : "POST",
			url : "lib/rcons.php",
			data : requireString,
			dataType : 'json',
			success : function(data){
					      rconsUpdate(data);
					  }
		});
		
		errorTimeout = window.setTimeout(rconsSendError, 15000);
		
	}
	
	//when receive the response, update the term area
	function rconsUpdate(data){
		window.clearTimeout(errorTimeout);
		errorArea.empty();
		if (data.term){
			termArea.empty().append(data.term);
			maxDelay = 200;
		} else{
			maxDelay = 2000;
		}
		
		receivingFlag = false;
		workingStatus.attr('class', 'off');
		sendTimeout = window.setTimeout(rconsSend, maxDelay);
	}
	
	function rconsSendError(){
		workingStatus.attr('class', 'off');
		errorArea.empty().append('Send require error.');
	}
	
	function rconsQueue(kc){
		keyBuf.unshift(kc);
		if (false == receivingFlag){
			window.clearTimeout(sendTimeout);
			sendTimeout = window.setTimeout(rconsSend, 1);
		}
	}
};
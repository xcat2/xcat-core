/***************************/
//@Author: Adrian "yEnS" Mato Gondelle & Ivan Guardado Castro
//@website: www.yensdesign.com
//@email: yensamg@gmail.com
//@license: Feel free to use it, but keep this credits please!					
/***************************/


var LoadBar = function(){  
    this.value = 0;  
    this.sources = Array();  
    this.sourcesDB = Array();  
    this.totalFiles = 0;  
    this.loadedFiles = 0;  
};  

LoadBar.prototype.show = function() {  
     this.locate();  
     document.getElementById("loadingZone").style.display = "block";  
};  
//Hide the loading bar interface  
LoadBar.prototype.hide = function() {  
     document.getElementById("loadingZone").style.display = "none";  
 };  
//Add all scripts to the DOM  
LoadBar.prototype.run = function(){  
     this.show();  
     var i;  
     for (i=0; i<this.sourcesDB.length; i++){  
         var source = this.sourcesDB[i];  
         var head = document.getElementsByTagName("head")[0];  
         var script = document.createElement("script");  
         script.type = "text/javascript";  
         script.src = "js/" + source  
	 //alert('loading js/' + source);
         head.appendChild(script);  
	 //myBar.loaded(script);
     }  
};  
//Center in the screen remember it from old tutorials?  
LoadBar.prototype.locate = function(){  
    var loadingZone = document.getElementById("loadingZone");  
    var windowWidth = document.documentElement.clientWidth;  
    var windowHeight = document.documentElement.clientHeight;  
    var popupHeight = loadingZone.clientHeight;  
    var popupWidth = loadingZone.clientWidth;  
    loadingZone.style.position = "absolute";  
    loadingZone.style.top = parseInt(windowHeight/2-popupHeight/2) + "px";  
    loadingZone.style.left = parseInt(windowWidth/2-popupWidth/2) + "px";  
};  
//Set the value position of the bar (Only 0-100 values are allowed)  
LoadBar.prototype.setValue = function(value){  
    if(value >= 0 && value <= 100){  
        document.getElementById("progressBar").style.width = value + "%";  
        document.getElementById("infoProgress").innerHTML = parseInt(value) + "%";  
    }  
};  
//Set the bottom text value  
LoadBar.prototype.setAction = function(action){  
    document.getElementById("infoLoading").innerHTML = action;  
};  
//Add the specified script to the list  
LoadBar.prototype.addScript = function(source){  
    this.totalFiles++;  
    this.sources[source] = source;  
    this.sourcesDB.push(source);  
};  
//Called when a script is loaded. Increment the progress value and check if all files are loaded  
LoadBar.prototype.loaded = function(file) {  
   this.loadedFiles++;  
    delete this.sources[file];  
   var pc = (this.loadedFiles * 100) / this.totalFiles;  
    this.setValue(pc);  
    this.setAction(file + " loaded");  
    //Are all files loaded?  
    if(this.loadedFiles == this.totalFiles){  
        //setTimeout("myBar.hide()",300);  
        myBar.hide();
        //load the reset button to try one more time!  
	//$(document).ready(function () {
	injs();
        //document.getElementById("wrapper").style.display = "none";
	//});
    }  
};  

//Global var to reference from other scripts  
var myBar = new LoadBar();  
   
//Checking resize window to recenter  
window.onresize = function(){  
    myBar.locate();  
};  
//Called on body load  

var xStart = function(){  
     myBar.addScript("jsTree/jquery.listen.js");  
     myBar.addScript("jsTree/tree_component.js");  
     myBar.addScript("jsTree/jquery.cookie.js");  
     myBar.addScript("jsTree/css.js");  
     myBar.addScript("jquery.form.js");  
     myBar.addScript("jquery.jeditable.mini.js");
     myBar.addScript("jquery.dataTables.min.js");
     myBar.addScript("hoverIntent.js");
     myBar.addScript("excanvas.js");
     myBar.addScript("superfish.js");  
     myBar.addScript("jquery.tablesorter.js");
     myBar.addScript("jquery.flot.js");
     myBar.addScript("jquery.flot.pie.js");
     myBar.addScript("excanvas.js");
     myBar.addScript("noderangetree.js");
     myBar.addScript("monitor.js");
     myBar.addScript("xcat.js");
     myBar.addScript("xcatauth.js");  
     myBar.addScript("config.js");  
     myBar.run();  
};  
//Called on click reset button  
restart = function(){  
    window.location.reload();  
};
setTimeout("myBar.loaded('xcatauth.js')", 500);

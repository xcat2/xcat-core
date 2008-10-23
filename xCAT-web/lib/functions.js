// Javascript functions that most pages need.
// Note: this is included by all pages, so only put functions in this file that most/all pages need.

function setCookie(name, value, path) {
value = escape(value);    // this is needed if value contains spaces, semicolons, or commas
document.cookie = name + '=' + value
				+ ';expires=' + (new Date("December 31, 2023")).toGMTString()
				+ ';path=' + path;
}

// Return a hash of the cookie names and values
function getCookies() {
//alert('"'+document.cookie+'"');
var cookies = document.cookie.split(/; */);
//alert(cookies[0]);
var cookret = new Object();   // this is the return value
for (i in cookies) { var pair = cookies[i].split('='); cookret[pair[0]] = unescape(pair[1]); }
return cookret;
}

// Check or uncheck all checkboxes that start with objectName
function selectAllCheckBoxes(element, objectName)
{
 //todo: use jQuery to accomplish this
 var sel = element.checked;
 var form = element.form;
 var searchstr = '^' + objectName + '\d';
 for(var i = 0; i < form.length; i++)
  {
   var e = form.elements[i];
   if (e.type == "checkbox" && e.name.search(searchstr) > -1) { e.checked = sel; }
  }
}

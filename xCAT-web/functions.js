
function setCookies(form)
{
var value = (form.rack.checked?1:0) + '&' + form.nodegrps.value + '&' + form.nodeRange.value;
setCookie('mainpage', value);
}

function setCookie(name, value)
{
value = escape(value);
value = value.replace(/\+/g, '%2B'); // The un_urlize() function in webmin works slightly differently than javascript escape()
document.cookie = name + '=' + value + ';expires=' + (new Date("December 31, 2023")).toGMTString();
}

function selectAll(element, objectName)
{
 var sel = element.checked;
 var form = element.form;
 var searchstr = '^' + objectName + '\\d';
 for(var i = 0; i < form.length; i++)
  {
   var e = form.elements[i];
   if (e.type == "checkbox" && e.name.search(searchstr) > -1) { e.checked = sel; }
  }
}

function isSelected(form, objectName)
{
var searchstr = '^' + objectName + '\\d';
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(searchstr) > -1 && e.checked) { return true; }
 }
return false;
}

function numSelected(form, objectName)
{
var searchstr = '^' + objectName + '\\d';
var j = 0;
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(searchstr) > -1 && e.checked)
   {
    if (++j == 2) { return j; }
   }
 }
return j;
}

function toggleSection(para, tableId)
{
 var t;  var i;
 var imageId = tableId + '-im';
 if (document.all) { t = document.all[tableId]; i = document.all[imageId]; }      // IE 4+
 else if (document.getElementById) { t = document.getElementById(tableId); i = document.getElementById(imageId); }    // Netscape 6
 else { alert('Cannot expand or collapse sections in this version of your browser.'); return false; }
 if (!t) { alert('Error: section ' + tableId + ' not found.'); return false; }

 if (!t.style.display || t.style.display == 'inline')   // the inner table is currently visible
  {
  t.style.display = 'none';
  para.title = 'Click to expand section';
  //if (txt) { txt = txt.replace(/^-/i, '+'); }
  i.src = 'images/plus-sign.gif';
  //i.alt = '+';
  }
 else   // the inner table is currently invisible
  {
  t.style.display = 'inline';
  para.title = 'Click to collapse section';
  //if (txt) { txt = txt.replace(/^\+/i, '-'); }
  i.src = 'images/minus-sign.gif';
  //i.alt = '-';
  }

 return true;
}


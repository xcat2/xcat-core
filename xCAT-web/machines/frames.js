// Javascript functions needed by the frames (racks) page, mostly
// to handle the check boxes that are actually images.

function imageCBClick(image, mode)
{
if (mode==1 || (mode==2 && (image.checked === undefined || !image.checked))) {
 image.src = '../images/checked-box.gif';
 image.checked = true;
} else {
 image.src = '../images/unchecked-box.gif';
 image.checked = false;
 var s=image.alt.split(/-/);
 var rackCB = document.frameForm['selAll'+s[0]+'Checkbox'];
 rackCB.checked = false;
}
}


function selectAll(element, rack)	// element is the select all checkbox, rack is the rack #
{
 var sel = element.checked;
 for (var i=0; i < document.images.length; i++) {
  var image = document.images[i];
  if (image.src.search(/checked-box\.gif$/)>-1 && image.alt.search('^'+rack+'-')>-1) { imageCBClick(image,sel); }
 }
}

/*
function isNodeSelected(form)
{
if (document.paramForm.rack.checked) { return (form.Nodes.value.length>0 || form.rackNodes.value.length>0); }
// we only continue here if it is the non-rack display
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(/^node\d/) > -1 && e.checked) { return true; }
 }
return false;
}

function numNodesSelected(form)
{
if (document.paramForm.rack.checked) {
 if (form.Nodes.value.length>0) { return 2; }  // just have to guess that the group or range has more than 1
 var val = form.rackNodes.value;
 var matches = val.match(/,/g);
 if (!matches) { return (val.length>0 ? 1 : 0); }
 else { return matches.length + 1; }
}
// we only continue here if it is the non-rack display
var j = 0;
for(var i = 0; i < form.length; i++)
 {
  var e = form.elements[i];
  if (e.type == "checkbox" && e.name.search(/^node\d/) > -1 && e.checked)
   {
    if (++j == 2) { return j; }
   }
 }
return j;
}

function gatherRackNodes(form)
{
 if (allSelected(form)) {
  if (document.paramForm.nodeRange.value.length > 0) { form.Nodes.value = document.paramForm.nodeRange.value; }
  else { form.Nodes.value = '+' + document.paramForm.nodegrps.value; }
  form.rackNodes.value='';
  return;
 }
 else { form.Nodes.value=''; }
 if (!document.paramForm.rack.checked) { form.rackNodes.value=''; return; }

 var nodes='';
 for (var i=0; i < document.images.length; i++) {
  var image = document.images[i];
  if (image.checked) { var s=image.alt.split(/-/); nodes += s[1] + ','; }
 }
 form.rackNodes.value = nodes.replace(/,$/, '');
}

function allSelected(form)
{
if (document.paramForm.rack.checked) {
 for(var i = 0; i < form.length; i++)
  {
   var e = form.elements[i];
   if (e.type=="checkbox" && e.name.search(/^selAll\d+Checkbox/)>-1 && !e.checked) { return false; }
  }
 return true;
}
else { return form.selAllCheckbox.checked; }   // non-rack display
}

function frameFormSubmit(form) {
gatherRackNodes(form);
if (form.nodesNeeded === undefined || form.nodesNeeded == 2) {    // need 1 or more nodes
 if (isNodeSelected(form)) { return true; }
 else { alert('Select one or more nodes before pressing an action button.');  return false; }
}
else if (form.nodesNeeded == 1) {                          // need exactly 1 node
 if (numNodesSelected(form) == 1) { return true; }
 else { alert('Exactly one node must be selected for this action.'); form.nodesNeeded=undefined; return false; }
}
else if (form.nodesNeeded == 0) { return true; }          // 0 or more nodes is ok
else { return true; }
}
*/


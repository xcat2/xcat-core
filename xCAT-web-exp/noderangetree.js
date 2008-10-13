var noderange="";
function updatenoderange() {
    myselection=nrtree.selected_arr;
    noderange="";
    for (node in myselection) {
        noderange+=myselection[node][0].id;
    }
    noderange=noderange.substring(1);
}

$(document).ready(function() {
    
    nrtree = new tree_component(); // -Tree begin
    nrtree.init($("#nrtree"),{
         rules: {
            multiple: "Ctrl"
        },
        ui: {
            animation: 250
        },
        callback : {
            onchange : updatenoderange
            }, 
        data : {
            type : "json",
            async : "true",
            url: "noderangesource.php"
        }
    });  //Tree finish
});

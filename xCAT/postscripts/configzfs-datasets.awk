# Validate dataset declarations before emitting any native creation options.
function fail(message) {
    print "ZFS datasets: " message > "/dev/stderr"
    bad=1
    exit 1
}
function path(text, absolute,    n,a,i) {
    if (absolute) {
        if (substr(text,1,1)!="/") return 0
        text=substr(text,2)
    }
    n=split(text,a,"/")
    if (!n || n>8) return 0
    for (i=1;i<=n;i++)
        if (a[i]!~/^[A-Za-z0-9_][A-Za-z0-9_.-]*$/ || length(a[i])>63) return 0
    return 1
}
function size(text,    unit,number) {
    if (text=="none" || text=="0") return "none"
    if (text!~/^[1-9][0-9]*[KMGTPEkmgtpe]?$/) fail("Invalid dataset size")
    unit=toupper(substr(text,length(text)))
    number=text+0
    if (unit~/[KMGTPE]/) number *= 1024^index("KMGTPE",unit)
    if (number>4503599627370496) fail("Dataset size exceeds 4 PiB")
    return sprintf("%.0f",number)
}
function add(name,mount,canmount,exec,setuid,atime) {
    known[name]=1
    value[name,"mountpoint"]=mount
    value[name,"canmount"]=canmount
    if (exec!="") value[name,"exec"]=exec
    if (setuid!="") value[name,"setuid"]=setuid
    if (atime!="") value[name,"atime"]=atime
}
function defaults() {
    add("zroot/ROOT","none","on","","","")
    add("zroot/ROOT/default","/","on","","","")
    add("zroot/home","/home","on","","","")
    add("zroot/tmp","/tmp","on","on","off","")
    add("zroot/usr","/usr","off","","","")
    add("zroot/usr/ports","/usr/ports","on","","off","")
    add("zroot/usr/src","/usr/src","on","","","")
    add("zroot/var","/var","off","","","")
    add("zroot/var/audit","/var/audit","on","off","off","")
    add("zroot/var/crash","/var/crash","on","off","off","")
    add("zroot/var/log","/var/log","on","off","off","")
    add("zroot/var/mail","/var/mail","on","","","on")
    add("zroot/var/tmp","/var/tmp","on","","off","")
}
BEGIN {
    property_count=split("mountpoint canmount exec setuid compression recordsize atime quota refquota reservation refreservation",property," ")
}
{
    bytes+=length($0)+1
    if (bytes>12288 || $0~/[^ -~]/) fail("Invalid or oversized declaration")
    if ($0~/^ *($|#)/) next
    if ($0~/^\[dataset /) {
        if ($0!~/\]$/) fail("Invalid dataset section")
        name=substr($0,10,length($0)-10)
        if (!path(name,0) || length(name)>255 || declared[name]++ || ++count>64)
            fail("Invalid or duplicate dataset name")
        next
    }
    if ($0!~/^[a-z_]+=[^=]+$/) fail("Expected a dataset property")
    key=$0; sub(/=.*/,"",key)
    setting=substr($0,length(key)+2)
    if (name=="") {
        if (key!~/^(format|kind|pool|mountpoint)$/ || (key in header)) fail("Invalid dataset header")
        header[key]=setting
    } else {
        if (key!~/^(mountpoint|compression|recordsize|atime|quota|refquota|reservation|refreservation)$/ || seen[name,key]++)
            fail("Unsupported or duplicate dataset property")
        input[name,key]=setting
    }
}
END {
    if (bad) exit 1
    pool=header["pool"]; root=header["mountpoint"]; os=(header["kind"]=="os")
    if ((expected_pool!="" && pool!=expected_pool) || (expected_kind!="" && header["kind"]!=expected_kind) ||
        (expected_mountpoint!="" && root!=expected_mountpoint)) fail("Dataset policy belongs to another pool")
    if (header["format"]!="xcat-freebsd-datasets-1" || !count ||
        (header["kind"]!="os" && header["kind"]!="data")) fail("Invalid dataset contract")
    if (os) {
        if (pool!="zroot" || root!="/") fail("Invalid OS dataset root")
        defaults()
    } else if (pool!~/^[a-z][a-z0-9_-]*$/ || length(pool)>63 || pool=="zroot" ||
        root!~/^\/(data|srv)\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/) fail("Invalid data dataset root")
    for (name in declared) {
        if (index(name,pool "/")!=1) fail("Dataset belongs to another pool")
        relative=substr(name,length(pool)+2)
        if (os && relative!~/^(home|tmp|usr|var|opt)(\/|$)/) fail("Reserved OS dataset")
        known[name]=1
    }
    for (name in known) {
        n=++total
        while (n>1 && order[n-1]>name) {order[n]=order[n-1]; n--}
        order[n]=name
    }
    for (i=1;i<=total;i++) {
        name=order[i]
        parent=name; sub(/\/[^\/]*$/,"",parent)
        leaf=name; sub(/.*\//,"",leaf)
        if (parent!=pool && !(parent in known)) fail("Declare the parent dataset first")
        if (!(name SUBSEP "mountpoint" in value)) {
            destination=(parent==pool ? root : value[parent,"mountpoint"]) "/" leaf
            if (os) destination="/" substr(name,length(pool)+2)
            value[name,"mountpoint"]=destination
            value[name,"canmount"]="on"
        }
        for (j=1;j<=property_count;j++) {
            key=property[j]
            if (!(name SUBSEP key in input)) continue
            setting=input[name,key]
            if (key=="mountpoint") {
                if (os) {
                    if (!path(setting,1)) fail("Invalid dataset mountpoint")
                    if (setting!=value[name,key]) fail("OS dataset mountpoints follow their dataset paths")
                } else {
                    prefix=(parent==pool ? root : value[parent,key]) "/"
                    if (index(setting,prefix)!=1) fail("Data dataset mounts outside its parent")
                    if (!path(substr(setting,length(prefix)+1),0)) fail("Invalid dataset mountpoint")
                }
            } else if (key=="compression") {
                if (setting!~/^(off|lz4|gzip(-[1-9])?|zstd(-([1-9]|1[0-9]))?)$/) fail("Invalid dataset compression")
                if (setting=="gzip-6") setting="gzip"
            } else if (key=="atime") {
                if (setting!~/^(on|off)$/) fail("Invalid dataset atime")
            } else {
                setting=size(setting)
                if (key=="recordsize") {
                    power=512
                    while (power<setting+0) power*=2
                    if (setting=="none" || power!=setting+0 || power>1048576) fail("Invalid dataset recordsize")
                }
            }
            value[name,key]=setting
        }
        destination=value[name,"mountpoint"]
        if (destination!="none" && destination!="/") {
            for (other in mounted) {
                if (destination==other || (index(destination,other "/")==1 && index(name,mounted[other] "/")!=1) ||
                    (index(other,destination "/")==1 && index(mounted[other],name "/")!=1)) fail("Overlapping dataset mountpoints")
            }
            mounted[destination]=name
        }
    }
    for (i=1;i<=total;i++) {
        name=order[i]; options=""
        for (j=1;j<=property_count;j++) {
            key=property[j]
            if (name SUBSEP key in value) options=options (options=="" ? "" : ",") key "=" value[name,key]
        }
        print name "\t" options
    }
}

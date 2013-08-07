function hashencode(){
        local map="$1"
         echo `echo $map | sed 's/\./xDOTx/g' | sed 's/:/xCOLONx/g' | sed 's/,/:xCOMMAx/g'`
}

function hashset(){
    local hashname="hash${1}${2}"
    local value=$3
    hashname=$(hashencode $hashname)
    eval "${hashname}='${value}'"
}

function hashget(){
    local hashname="hash${1}${2}"
    hashname=$(hashencode $hashname)
    eval echo "\$${hashname}"
}

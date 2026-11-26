config_field() {
    grep "$1" /tmp/ipmicfg.xml | awk -F\> '{print $2}' | awk -F\< '{print $1}'
}

lan_field() {
    ipmitool -d "$1" lan print "$2" | grep "$3" |
        if [ "$#" -eq 4 ]; then
            grep -v "$4"
        else
            cat
        fi | awk -F': ' '{print $2}'
}

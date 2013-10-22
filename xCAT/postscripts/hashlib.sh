#!/bin/sh

## defined HASH functions here
hput() {
    eval "HASH""$1""$2"='$3'
}

hget() {
    eval echo '${'"HASH$1$2"'}'
}

hkeys() {
    set | grep -o "^HASH${1}[[:alnum:]]*=" | sed -re "s/^HASH${1}(.*)=/\\1/g"
}



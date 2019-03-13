(while ! /bin/screen -ls|/bin/grep console > /dev/null; do /bin/sleep 1; done; /bin/python /usr/bin/autocons.py) &

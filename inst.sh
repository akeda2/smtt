#!/bin/bash

sudo install -m 755 smtt.sh /usr/local/bin/smtt && echo "smtt install SUCCESS!" || echo "smtt install FAIL!"
sudo install -m 755 turbot.sh /usr/local/bin/turbot && echo "turbot install SUCCESS!" || echo "turbot install FAIL!"

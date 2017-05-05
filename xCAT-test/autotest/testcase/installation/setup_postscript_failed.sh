#!/bin/bash
cat >> /install/postscripts/test <<EOF
#!/bin/bash
echo "test"
exit 1
EOF

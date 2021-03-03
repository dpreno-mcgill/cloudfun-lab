#!/bin/bash
apt update
apt install -y apache2
cat <<EOF > /var/www/html/index.html
<html><body>
<h2>Welcome to your YCIT-018 Lab Project</h2>
<h3>Your requirements seems to be working well!</h3>
</body></html>
EOF
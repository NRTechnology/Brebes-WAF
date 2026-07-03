1. Install Ubuntu Server 24
2. Install Nginxsudo
   - apt install nginx
   - sudo systemctl enable nginx
   - sudo systemctl start nginx
3. Install modsecurity
   - sudo apt install -y \
     libmodsecurity3 \
     libnginx-mod-http-modsecurity \
     modsecurity-crs
4. 
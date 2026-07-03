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
4. change directory to /opt
   - cd /opt
5. git clone main branch
   - git clone  https://github.com/NRTechnology/Brebes-WAF.git
6. change directory to /opt/Brebes-WAF
   - cd /opt/Brebes-WAF
7. add executable permition to /opt/Brebes-WAF/script/deploy.sh
   - chmod +x /opt/Brebes-WAF/script/deploy.sh
8. execute deploy.sh
   - /opt/Brebes-WAF/script/deploy.sh
9.  
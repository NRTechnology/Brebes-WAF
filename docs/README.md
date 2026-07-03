# BREBES-WAF Installation Guide

## Prerequisites

- Ubuntu Server 24.04 LTS
- Git
- Internet Connection

---

## 1. Install Ubuntu Server 24.04 LTS

Install Ubuntu Server 24.04 LTS on your system.

---

## 2. Install Nginx

```bash
sudo apt update
sudo apt install -y nginx

sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 3. Install ModSecurity

```bash
sudo apt install -y \
    libmodsecurity3 \
    libnginx-mod-http-modsecurity \
    modsecurity-crs
```

---

## 4. Change to the /opt Directory

```bash
cd /opt
```

---

## 5. Clone the Repository

Clone the latest stable (main) branch.

```bash
git clone https://github.com/NRTechnology/Brebes-WAF.git
```

---

## 6. Configure Nginx

Configure Nginx to enable ModSecurity and include the BREBES-WAF configuration.

See the example configuration files in the **nginx/** directory.

---

## 7. Change to the BREBES-WAF Directory

```bash
cd /opt/Brebes-WAF
```

---

## 8. Make the Deployment Script Executable

```bash
chmod +x scripts/deploy.sh
```

---

## 9. Deploy BREBES-WAF

```bash
./scripts/deploy.sh
```

---

## 10. Verify the Installation

Verify that Nginx is running correctly.

```bash
sudo nginx -t
sudo systemctl status nginx
```

You should see a successful deployment similar to:

```
Deployment Successful

Loaded Rules : XX
Include File : /etc/nginx/modsecurity_includes.conf
```
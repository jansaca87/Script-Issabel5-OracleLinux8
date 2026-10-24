# Technical datasheet of the resulting system
**Objective:** record, measured rather than assumed, the state of the
system produced by `issabel5-netinstall-el8.sh`.

**Date:** 22 October 2026
**Environment:** Oracle Linux 8.10 on VMware Workstation, 2 vCPU, 4 GB RAM,
NVMe disk, NAT networking.
**Bilingual document:** this one is in English; the Spanish version is in
`CHARACTERIZATION.md`.

---

## 1. How it was measured

After each turn of the determinism harness, the driver runs a
characterisation script inside the guest and stores its raw output in
`determinismo/char-run<N>.txt`. This document reproduces that output
organised by block. Nothing here comes from anything other than a real
measurement on the installed system.

The characterisation script (`determinismo/char-run1.sh`) collects:

- host identity and operating system version;
- running kernel and default boot kernel;
- SELinux state, own policy module and contexts;
- active and enabled state of every relevant service;
- Asterisk version;
- listening ports (the exposure of 3306 and 5038 is checked here);
- installed packages and versions of the key ones;
- Issabel configuration files (without passwords) and their checksums.

---

## 2. Measured system state
### System identity

```
issabel5cc.mirsaso.com
NAME="Oracle Linux Server"
VERSION="8.10"
ID="ol"
```

### Kernel

```
4.18.0-553.174.1.el8_10.x86_64
/boot/vmlinuz-4.18.0-553.174.1.el8_10.x86_64
```

### SELinux

```
Enforcing
issabel_selinux
```

### SELinux contexts (fcontext)

```
/etc/amportal\.conf                                all files          system_u:object_r:issabel_conf_t:s0 
/etc/issabel\.conf                                 all files          system_u:object_r:issabel_conf_t:s0 
```

### Port 5038 (AMI) in the policy

```
asterisk_port_t                tcp      5038, 1720
```

### Services

```
asterisk active=active enabled=enabled
mariadb active=active enabled=enabled
httpd active=active enabled=enabled
firewalld active=active enabled=enabled
sshd active=active enabled=enabled
```

### Asterisk version

```
Asterisk 20.12.0 built by root @ rocky8 on a x86_64 running Linux on 2025-04-24 20:42:39 UTC
```

### Listening ports

```
0.0.0.0:110
0.0.0.0:143
0.0.0.0:1720
0.0.0.0:22
0.0.0.0:25
0.0.0.0:4190
0.0.0.0:4559
0.0.0.0:5066
0.0.0.0:8088
0.0.0.0:993
0.0.0.0:995
[::]:110
127.0.0.1:20004
127.0.0.1:3306
127.0.0.1:5038
[::]:143
[::]:22
[::]:25
[::]:4190
*:443
*:80
[::]:993
[::]:995
```

### Installed packages

```
asterisk20-20.12.0-1.el8.x86_64
asterisk20-addons-20.12.0-1.el8.x86_64
asterisk20-addons-bluetooth-20.12.0-1.el8.x86_64
asterisk20-addons-core-20.12.0-1.el8.x86_64
asterisk20-addons-mysql-20.12.0-1.el8.x86_64
asterisk20-addons-ooh323-20.12.0-1.el8.x86_64
asterisk20-configs-20.12.0-1.el8.x86_64
asterisk20-core-20.12.0-1.el8.x86_64
asterisk20-curl-20.12.0-1.el8.x86_64
asterisk20-dahdi-20.12.0-1.el8.x86_64
asterisk20-devel-20.12.0-1.el8.x86_64
asterisk20-doc-20.12.0-1.el8.x86_64
asterisk20-odbc-20.12.0-1.el8.x86_64
asterisk20-resample-20.12.0-1.el8.x86_64
asterisk20-voicemail-20.12.0-1.el8.x86_64
asterisk-sounds-en-gsm-1.5-1.el7.centos.noarch
httpd-2.4.37-65.0.1.module+el8.10.0+91023+3994037c.8.x86_64
httpd-filesystem-2.4.37-65.0.1.module+el8.10.0+91023+3994037c.8.noarch
httpd-tools-2.4.37-65.0.1.module+el8.10.0+91023+3994037c.8.x86_64
issabel-5.0.0-1.noarch
issabel-addons-5.0.0-1.noarch
issabel-agenda-5.0.0-3.noarch
issabel-asterisk-sounds-1.2.3-2.noarch
issabel-centos8-provides-1-1.el8.x86_64
issabel-config_helpers-5.0.0-1.noarch
issabel-el8-compat-1.0-1.el8.x86_64
issabel-email_admin-5.0.0-2.noarch
issabel-endpointconfig2-5.0.0-1.el8.noarch
issabel-extras-5.0.0-1.noarch
issabel-fax-5.0.0-1.noarch
issabel-firstboot-5.0.0-2.noarch
issabel-framework-5.0.0-5.noarch
issabel-geoip-1.6.12-3.x86_64
issabel-license-5.0.0-1.x86_64
issabel-my_extension-5.0.0-1.noarch
issabel-packetbl-1.0-3.x86_64
issabelPBX-2.12.0-5.noarch
issabel-pbx-5.0.0-4.noarch
issabel-portknock-4.0.0-2.x86_64
issabel-prosody-auth-1.0-3.noarch
issabel-reports-5.0.0-3.noarch
issabel-security-5.0.0-1.noarch
issabel-system-5.0.0-5.noarch
mariadb-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-backup-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-common-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-connector-c-3.1.11-3.el8_10.x86_64
mariadb-connector-c-config-3.1.11-3.el8_10.noarch
mariadb-connector-odbc-3.1.12-1.el8.x86_64
mariadb-errmsg-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-gssapi-server-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-server-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
mariadb-server-utils-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
php-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-bcmath-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-cli-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-common-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-fedora-autoloader-1.0.1-7.el8.noarch
php-fpm-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-gd-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-IDNA_Convert-0.8.0-14.el8.noarch
php-imap-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-intl-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-ioncubeloader-2.0.0-4.x86_64
php-jpgraph-3.0.7-2.noarch
php-json-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-mbstring-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-mysqlnd-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-opcache-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-pdo-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-pear-1.10.18-4.el8.remi.noarch
php-pear-DB-1.12.1-1.el8.remi.noarch
php-pecl-imagick-3.8.1-4.module_php.7.4.el8.remi.x86_64
php-pecl-mcrypt-1.0.9-1.el8.remi.7.4.x86_64
php-pecl-zip-1.22.8-1.module_php.7.4.el8.remi.x86_64
php-PHPMailer-5.2.28-6.el8.remi.noarch
php-process-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-rlerdorf-geoip-1.4.0-1.module_php.7.4.el8.remi.x86_64
php-simplepie-1.5.6-1.el8.remi.noarch
php-Smarty-3.1.48-2.el8.noarch
php-soap-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-sodium-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-tcpdf-6.11.3-1.el8.remi.noarch
php-tidy-7.4.33-31.module_php.7.4.el8.remi.x86_64
php-xml-7.4.33-31.module_php.7.4.el8.remi.x86_64
```

### Versions of the key packages

```
asterisk20-20.12.0-1.el8.x86_64
php-mysqlnd-7.4.33-31.module_php.7.4.el8.remi.x86_64
mariadb-server-10.3.39-2.0.1.module+el8.10.0+90769+0aa21600.x86_64
httpd-2.4.37-65.0.1.module+el8.10.0+91023+3994037c.8.x86_64
```

### Issabel configuration (without passwords)

```
pbxapijwtsecret=5SmdvsOcBeVDbtpVV62hKzYG2DhaidepmhvMSbdaBzs=
```

### Web interface

```
assets
bootstrap.php
config.php
functions.inc.php
helpers
i18n
images
index.php
issabel_issabelpbx_auth.php
libraries
```

### Initialisation state

```
0
```

### Checksums of the configuration files

```
8bacdbaafd0b3f6af21ee376d3128007474627d5f8242583a02466f1c1a7fd16  /etc/issabel.conf
7498bab78d0450a90cf9743d622cfa93bfab8a11fd27efbbd8d6f2669b7ae4a2  /etc/amportal.conf
749014aeecf28e3ab286501bde9e13134c1eed06357ddfba9c5b5ef89e8a174a  /etc/asterisk/asterisk.conf
```

## 3. Comparison of the two turns

The sections that **differ** between turn 1 and turn 2 are:

- `issabel conf (sin contrasenas)`
- `hash de ficheros clave`

The only variation is `pbxapijwtsecret`, the JWT secret the
installer generates randomly on every run; it is also why the
`/etc/issabel.conf` checksum changes. Everything else measured -
identity, kernel, SELinux, services, versions, ports, packages -
is **identical byte for byte**: the same starting point produces
the same system.

---

## 4. How to reproduce these measurements

```bash
# Characterise the installed system, inside the guest:
sudo bash determinismo/char-run1.sh > char-run1.txt

# Repeat the full two-turn cycle (see DETERMINISM-en.md):
python repeat-test.py 2
```

The functional verifier (`issabel-verify.sh`) is the complementary
acceptance test: it checks the state of the services, the ports, SELinux,
the database and the web interface. The characterisation shown here is
the picture of the system **after** the verifier has reported `FAIL: 0`.

---

## 5. Related documentation

| Document | Content |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | Script user manual, in Spanish. |
| [MANUAL-en.md](MANUAL-en.md) | Script user manual, in English. |
| [DETERMINISM-en.md](DETERMINISM-en.md) | The determinism test. |
| [APPLIANCE-en.md](APPLIANCE-en.md) | Self-installing appliance. |

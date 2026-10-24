# Issabel 5 Installation Manual for EL8

**Script:** `issabel5-netinstall-el8.sh`
**Platform:** Oracle Linux 8 / RHEL 8 / Rocky 8 / AlmaLinux 8 (x86_64)
**Asterisk:** 20 (configurable with `ASTVER`)
**Lab-tested:** Oracle Linux 8.10, on October 21, 2026
**Bilingual documentation:** this is the English version; the Spanish version
is in `MANUAL-es.md`.

---

## 1. What this script does

The script installs a complete **Issabel 5** PBX from scratch on a
pre-installed EL8 server, with no operator input. Specifically:

1. Verifies the system is EL8 x86_64 and has `dnf`.
2. Enables the repositories Issabel needs: EPEL, CodeReady Builder and Remi
   (for PHP 7.4).
3. Imports the official Issabel GPG key and **verifies its fingerprint**
   before trusting it.
4. Builds three compatibility RPMs that Issabel requires but that exist in no
   EL8 repository (`dahdi`, `libopenr2`, `python-cjson`).
5. Installs the full stack: Apache, MariaDB, PHP 7.4, Asterisk 20, the Issabel
   packages and the dependencies their post-install scripts assume.
6. Leaves MariaDB and the Asterisk AMI listening on **loopback only**.
7. Creates the IssabelPBX database schema and sets the passwords.
8. Installs a custom SELinux module (`issabel_selinux`), labels the
   directories the web panel uses, and leaves the system in **enforcing**.
9. Configures `firewalld` restricting SSH and HTTPS to your management
   network.

On completion the server is a working Issabel 5 PBX, with its web panel on
port 443 and Asterisk 20 running.

---

## 2. Requirements

### 2.1 System

| Requirement | Value |
|---|---|
| Operating system | Oracle Linux 8, RHEL 8, Rocky 8 or AlmaLinux 8 |
| Architecture | x86_64 (64-bit) |
| Kernel | **RHCK** (`4.18.0-*el8*`). Oracle's UEK does not work |
| Privileges | root |
| Disk space | 20 GB free minimum (40 GB recommended) |
| Memory | 2 GB minimum, 4 GB recommended |
| Network | outbound HTTPS (yum.oracle.com, repo.issabel.org, dl.fedoraproject.org, rpms.remirepo.net) |
| Hostname | must be set **and** resolvable (FQDN) before installing |

The FQDN matters: Issabel generates the Asterisk configuration and the
extensions from the hostname, and a hostname without a domain produces
configurations that later fail to load.

### 2.2 Packages that must already be present

The script needs these tools on the system **before** it runs:

```bash
dnf install -y dnf-plugins-core curl gpg rpm-build gcc make policycoreutils \
               policycoreutils-python-utils python3
```

`gcc` and `rpm-build` are mandatory: the script compiles the `libopenr2` stub
and builds the compatibility RPMs. If they are missing, the installation stops
with an explicit error.

### 2.3 About Oracle's UEK kernel

On Oracle Linux the default kernel is the **UEK**, but the kernel modules
Issabel installs (`xtables-addons`, `dahdi`) are built for the RHEL **RHCK**.
The script therefore checks the kernel up front:

- If the default kernel is the UEK and an RHCK is installed, the script
  **sets the RHCK as the boot kernel** and exits with **exit code 42**,
  telling you to reboot and run it again.
- If no RHCK is installed, the script stops and explains how to install one.
- To proceed on the UEK at your own risk, use `ALLOW_UEK=1`.

This is **by design**, not a failure. The full install cycle is:

```bash
MGMT_CIDR=10.0.0.0/24 ./issabel5-netinstall-el8.sh   # exits 42
reboot                                                  # now boots the RHCK
MGMT_CIDR=10.0.0.0/24 ./issabel5-netinstall-el8.sh   # exits 0
```

### 2.4 Firewall and access

If your corporate firewall blocks egress to the Issabel repositories, the
script will fail downloading the GPG key or the RPMs. Check first:

```bash
curl -I https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
curl -I https://rpms.remirepo.net/enterprise/remi-release-8.rpm
```

---

## 3. Usage

### 3.1 Minimal run

```bash
# 1) Copy the script to the server
scp issabel5-netinstall-el8.sh user@server:/root/

# 2) Log in and run it as root
ssh user@server
sudo -i
MGMT_CIDR=192.168.1.0/24 bash /root/issabel5-netinstall-el8.sh
```

`MGMT_CIDR` is **mandatory** with the default firewall mode
(`FW_MODE=firewalld`): it is the network from which SSH and HTTPS access is
allowed. Get it wrong and the script locks you out of the host — which is why
it checks that your own SSH address is inside that range before applying the
rules.

### 3.2 Unattended run (recommended)

```bash
MGMT_CIDR=192.168.1.0/24 \
MYSQL_ROOT_PWD='StrongDb.2026' \
ADMIN_PWD='StrongWeb.2026' \
nohup bash /root/issabel5-netinstall-el8.sh > /root/issabel-install.log 2>&1 &
```

The script **never prompts**: no `dialog`, no graphical installer, nothing
read from stdin. It is safe to launch with `nohup`, from `cron`, or from an
automation pipeline.

### 3.3 Running it as a first-boot appliance

To install on new VMs with no intervention, use the self-installing ISO. See
[APPLIANCE.md](APPLIANCE.md).

---

## 4. Environment variables

All optional except `MGMT_CIDR` (mandatory with `FW_MODE=firewalld`).

| Variable | Default | Purpose |
|---|---|---|
| `MGMT_CIDR` | *(empty)* | Management network allowed to reach SSH and HTTPS. CIDR notation, e.g. `10.0.0.0/24`. **Required** with `FW_MODE=firewalld`. |
| `ASTVER` | `20` | Asterisk version to install (20, 18, 16…). |
| `ADDONS` | `blocklist` | Issabel addons, comma separated. Values: `blocklist`, `licensed`, `wanpipe`, `none`. |
| `FW_MODE` | `firewalld` | `firewalld` (hardened, management network only) or `issabel` (like the original script: leaves the host open). |
| `ALLOW_UEK` | `0` | `1` allows installing even when the default kernel is the UEK. |
| `ALLOW_NOGPG` | `0` | `1` retries a package without signature verification. Diagnostics only. |
| `ISSABEL_GPG_FPR` | `40D9EB22406CA314E78AC1015C0137F11762DF3D` | Expected fingerprint of the Issabel key. The script stops if it does not match. |
| `SKIP_PASSWORDS` | `0` | `1` does not set the passwords (you must run `issabel-admin-passwords --cli init` yourself). |
| `SKIP_UPDATE` | `0` | `1` skips `dnf update` (saves time, leaves the system unpatched). |
| `REBOOT` | `0` | `1` reboots the host when the installation finishes. |
| `COMPAT` | `1` | `0` does not build the compatibility RPMs (the installation **will fail**). |
| `MYSQL_ROOT_PWD` | `Issabel5Db.2026` | MariaDB root password on first boot. |
| `ADMIN_PWD` | `Issabel5Web.2026` | Password for the `admin` web-panel and AMI user. |
| `LANG_MODE` | `auto` | Language of the messages and the log: `es`, `en` or `auto` (picks based on the system locale). |

### 4.1 About the passwords

The default passwords **are public and are in this manual**. They are fine for
a lab but **are not acceptable in production**.

- The script only applies them the **first** time it runs. Later runs reuse
  the credentials already stored in `/etc/issabel.conf`.
- To keep them out of the code, pass them through the environment (see 3.2)
  or change them after the installation.
- Changing the MariaDB root password is **not** done with `ALTER USER`: on
  EL8 the MariaDB root authenticates via `unix_socket`. Use
  `issabel-admin-passwords --cli change <pwd_mysql> <pwd_admin>` so Issabel
  stays in sync.

---

## 5. Expected results

### 5.1 On successful completion

The script prints to the screen and to the log:

```
[2026-10-21 23:58:12] Installing IssabelPBX (database schema, web files, modules and Asterisk config)
[2026-10-21 23:58:40] IssabelPBX schema installed
[2026-10-21 23:58:41] SELinux module 'issabel_selinux' installed
[2026-10-21 23:58:48] SELinux enforcing with the module and the Issabel labels applied
[2026-10-21 23:58:48] Listening sockets (check 3306 and 5038: loopback only)
[2026-10-21 23:58:49] Done. Reboot, then: ./issabel5-netinstall-el8.sh --audit
```

And the **exit code is 0**.

### 5.2 Final system state

| Item | Expected state |
|---|---|
| `asterisk` | active and enabled |
| `mariadb` | active and enabled |
| `httpd` | enabled (with SELinux enforcing) |
| `firewalld` | active, with SSH and HTTPS restricted to `MGMT_CIDR` |
| SELinux | `Enforcing`, with the `issabel_selinux` module loaded |
| Port 5038 (AMI) | listening on `127.0.0.1` only |
| Port 3306 (MariaDB) | listening on `127.0.0.1` only |
| Port 443 (HTTPS) | listening on all interfaces |
| Web panel | `https://<FQDN>/` returns `200` |
| Database | `asterisk` database with the `ampusers` table and the `admin` user |
| `/etc/issabel.conf` | contains `mysqlrootpwd` and `amiadminpwd` |
| `/var/lib/issabel-netinstall/passwords_done` | exists (installation-complete marker) |

### 5.3 Exit codes

| Code | Meaning | What to do |
|---|---|---|
| `0` | Installation completed | Reboot and run `--audit` to review. |
| `42` | The host was prepared but must be rebooted and the script re-run (UEK → RHCK case) | Reboot and run the script again. |
| `1` | Real failure | Check `/var/log/issabel-netinstall-errors.txt` and `/var/log/issabel-netinstall.log`. |

---

## 6. Verification

The repository includes a standalone functional verifier:

```bash
scp issabel-verify.sh user@server:/root/
ssh user@server
sudo bash /root/issabel-verify.sh
```

It checks 6 groups: services, MariaDB, Asterisk/AMI, the web panel (with a
real login against the panel), socket exposure, and hardening (SELinux,
modules, permissions). It returns `0` if everything passes and `1` otherwise,
and prints a summary:

```
== Resultado ==
  PASS: 31   FAIL: 0
```

### 6.1 Quick audit from the script itself

```bash
sudo ./issabel5-netinstall-el8.sh --audit
```

It prints the listening sockets, checks that 3306 and 5038 are not exposed,
validates the MariaDB password, checks the database schema, the web panel,
the SQL spool, the Asterisk state and the SELinux state.

### 6.2 Manual checks

```bash
# Asterisk answers
sudo asterisk -rx 'core show version'

# The AMI accepts the login
sudo nc 127.0.0.1 5038 <<< $'action: login\r\nusername: admin\r\nsecret: Issabel5Web.2026\r\n\r\naction: ping\r\n\r\n'

# The web panel responds
curl -k -o /dev/null -w '%{http_code}\n' https://localhost/

# SELinux and its module
getenforce
sudo semodule -l | grep issabel

# Nobody exposes MariaDB
sudo ss -tlnp | grep -E '3306|5038'
```

---

## 7. Secure by default

What the script does to leave the host in a defensive posture:

- **MariaDB on loopback only.** `bind-address=127.0.0.1` in
  `/etc/my.cnf.d/zz-issabel-hardening.cnf`, with mode `644` (mysqld reads it
  as the `mysql` user: with `600` it silently ignores it and keeps listening
  on every interface).
- **AMI on loopback only.** `bindaddr = 127.0.0.1` in
  `/etc/asterisk/manager.conf`. The web panel talks to Asterisk over
  loopback.
- **GPG signatures verified.** The Issabel key is imported and its
  fingerprint checked against `ISSABEL_GPG_FPR`. `--nogpgcheck` is never used
  unless you explicitly ask with `ALLOW_NOGPG=1`.
- **Sanitized repositories.** The Issabel 4 repository (EL7, with
  `gpgcheck=0`) that the original script left behind is removed.
- **SELinux enforcing** with a custom module, instead of being left in
  `permissive` as the original netinstall did.
- **Restricted firewall.** The default `firewalld` services are removed and
  SSH and HTTPS are allowed only from `MGMT_CIDR`.
- **No proprietary addons** unless requested with `ADDONS=licensed`.
- **Restrictive log permissions:** `/var/log/issabel-netinstall.log` and
  `/var/log/issabel-netinstall-errors.txt`, mode `600`.
- **The interactive Issabel installer** (`issabel-firstboot`) is disabled: on
  a host with no console it would hang on first boot.

### 7.1 What the script **does not** do

- It does not open the SIP ports (5060/5061) or the RTP range. That decision
  belongs to whoever operates the system, because opening them without
  knowing which trunks exist is the usual cause of accidental exposure. The
  script prints the exact rule you need:

  ```bash
  firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=203.0.113.10 port port=5060 protocol=udp accept'
  ```

  Remember to open the RTP range defined in `rtp.conf` towards the required
  sources as well.
- It does not change passwords that are already set.
- It does not leave the AMI exposed to the network.

---

## 8. Post-installation

### 8.1 First access to the panel

```
https://<server-FQDN>/
```

User: `admin` — Password: `ADMIN_PWD` (default `Issabel5Web.2026`).

The TLS certificate is self-signed, so the browser will warn about it. That
is normal in a lab; in production use a certificate from a certification
authority.

### 8.2 Changing the default passwords

```bash
# MariaDB root password and the panel's admin user
sudo /usr/bin/issabel-admin-passwords --cli change 'NEW_DB_PASSWORD' 'NEW_ADMIN_PASSWORD'
```

Afterwards the web panel needs a session reload for the AMI to accept the new
password.

### 8.3 Opening SIP and RTP

Only once you are clear about which trunks and which addresses will connect:

```bash
# SIP
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=TRUNK_IP port port=5060 protocol=udp accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=TRUNK_IP port port=5060 protocol=tcp accept'
# RTP (adjust the range to your rtp.conf)
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=TRUNK_IP port port="10000-20000" protocol=udp accept'
sudo firewall-cmd --reload
```

Do not enable Issabel's *Firewall* module while `firewalld` manages the
rules: they would fight each other.

### 8.4 Backups

What needs backing up:

| What | Where |
|---|---|
| Issabel database | `mysqldump -u root -p asterisk` and `asteriskcdrdb` |
| Asterisk configuration | `/etc/asterisk/` |
| Panel configuration | `/etc/amportal.conf`, `/etc/issabel.conf` |
| Modules and plugins | `/var/www/html/admin/modules/` |
| Recordings | `/var/spool/asterisk/monitor/` |

---

## 9. Troubleshooting

### 9.1 The script exits with 42

**Meaning:** the default kernel is Oracle's UEK and the RHCK must be booted.

**Fix:** reboot and run the script again. The script already set the RHCK as
the boot kernel.

```bash
grubby --default-kernel        # must show /boot/vmlinuz-4.18.0-...
reboot
```

### 9.2 "your SSH IP is outside MGMT_CIDR"

**Meaning:** if you apply the rule with a range that does not include your
address, you lock yourself out of the server.

**Fix:** use the right network. To find it:

```bash
echo $SSH_CLIENT
```

### 9.3 "could not download the Issabel GPG key"

**Meaning:** no egress to `repo.issabel.org`, or the mirror is down.

**Fix:** check connectivity and proxies:

```bash
curl -v https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
```

### 9.4 "fingerprint does not match ISSABEL_GPG_FPR"

**Meaning:** the downloaded key is not the expected one. This could be a
substitution attack or a compromised mirror.

**Fix:** **do not continue.** Verify the key through another channel and, if
legitimate, update `ISSABEL_GPG_FPR` with the correct fingerprint.

### 9.5 "install_amp --installdb failed"

**Meaning:** Issabel's main script could not create the database schema.

**Fix:** see the detail in `/tmp/install_amp.log` and in
`journalctl -u asterisk`. The most common cause is Asterisk not running:
`install_amp` aborts if it cannot find Asterisk up. Resolve it with
`sudo systemctl start asterisk` and re-run the script.

### 9.6 "could not compile the SELinux module"

**Meaning:** `checkmodule` or `semodule_package` is missing.

**Fix:**

```bash
sudo dnf install -y checkpolicy policycoreutils policycoreutils-python-utils
```

If it persists, check `/tmp/issabel-selinux.err`.

### 9.7 The web panel does not load

```bash
sudo systemctl status httpd
sudo tail -50 /var/log/httpd/error_log
sudo ausearch -m AVC -ts recent | tail -30   # SELinux denials
```

Also check that port 443 is open from your management network.

### 9.8 Asterisk does not start with SELinux enforcing

```bash
sudo ausearch -m AVC -ts recent | tail -40
sudo journalctl -u asterisk -n 100 --no-pager
```

The `issabel_selinux` module should cover the usual cases (mapping the
SQLite astdb, the panel accessing the Asterisk configuration, connecting to
the AMI). If a new denial appears, add the rule to the `issabel-selinux.te`
file and recompile it.

### 9.9 The script seems to do nothing

Read the log, not stdout:

```bash
sudo tail -f /var/log/issabel-netinstall.log
sudo cat /var/log/issabel-netinstall-errors.txt
```

---

## 10. Timing and resources

Measured in the lab (Oracle Linux 8.10, 2 vCPU, 4 GB RAM, NVMe disk,
100 Mbps network):

| Phase | Approximate time |
|---|---|
| Enabling repositories and importing the GPG key | 1 – 2 min |
| `dnf update` of the system | 3 – 5 min |
| Downloading and installing packages (Asterisk 20, Issabel, PHP 7.4) | 8 – 12 min |
| Schema creation, passwords and SELinux module | 2 – 3 min |
| **Total (with `dnf update`)** | **15 – 22 min** |
| **Total (with `SKIP_UPDATE=1`)** | **10 – 15 min** |
| Reboot and first startup | 1 – 2 min |

Disk space used by the installation: about **4 GB** (Asterisk packages,
PHP 7.4, Issabel, sound files and the database).

---

## 11. Idempotency

The script can safely be re-run:

- It detects that Issabel is already initialised (database schema, key in
  `/etc/issabel.conf` and the `passwords_done` marker) and does not repeat the
  initialisation.
- Compatibility RPMs that are already installed are not rebuilt.
- Passwords are only applied the first time; afterwards the ones already in
  `/etc/issabel.conf` are re-applied.

This is the basis of the kernel reinstall cycle: run, reboot, run again.

---

## 12. Quick reference

```bash
# Typical lab installation
MGMT_CIDR=192.168.1.0/24 bash issabel5-netinstall-el8.sh

# Unattended installation with your own passwords
MGMT_CIDR=192.168.1.0/24 \
MYSQL_ROOT_PWD='...' ADMIN_PWD='...' \
bash issabel5-netinstall-el8.sh

# Audit the current state only
sudo ./issabel5-netinstall-el8.sh --audit

# Full functional verification
sudo bash issabel-verify.sh

# Watch the log live
sudo tail -f /var/log/issabel-netinstall.log
```

---

## 13. Related documentation

| Document | Content |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | This manual, in Spanish. |
| [APPLIANCE.md](APPLIANCE.md) | The self-installing ISO: what it is, how to use it, how to build it. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | The technical datasheet of the resulting system, measured in the lab. |
| [DETERMINISM.md](DETERMINISM.md) | The deterministic behaviour test: method, results and evidence. |

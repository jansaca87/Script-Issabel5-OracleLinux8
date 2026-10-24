# Issabel 5 Self-Installing Appliance for EL8

**ISO:** `autoinst-issabel5-ol8.iso`
**Purpose:** install a fully working Issabel 5 + Asterisk 20 server on a new
VM by booting from the ISO, with no intervention.
**Bilingual documentation:** this document is in English; the Spanish version
is in `APPLIANCE.md`.

---

## 1. What it is

A self-installing ISO that does three things in a single boot:

1. **Installs Oracle Linux 8.10** unattended via a kickstart
   (`ks-appliance.cfg`): partitioning, repositories, user account, SSH, SELinux
   enforcing.
2. **Prepares the first boot**: copies the verified installer, the verifier
   and the SELinux module into the system, and enables the
   `issabel-appliance.service` unit.
3. **Installs and verifies Issabel 5** during that first boot, without
   touching the console, and leaves the result in a readable status file.

Result: **new VM → boot the ISO → wait ~25-30 min → working, verified
Issabel 5 PBX**.

The difference from running the script by hand is that the ISO also covers
the base operating system installation, which is the slow, manual part.

---

## 2. Requirements

| Requirement | Detail |
|---|---|
| VM | x86_64, 2 vCPU, 4 GB RAM, 40 GB disk |
| Network | DHCP and outbound HTTPS (Oracle Linux, EPEL, Remi, repo.issabel.org) |
| Boot | The VM must boot from the ISO (BIOS or UEFI) |
| Time | 25-30 min to the final state |

The kickstart **sets the RHCK as the boot kernel** in `%post`. This matters:
the Issabel installer requires the RHCK, so the appliance never hits the
"reboot and re-run" case (exit code 42) that does occur when the script runs
on a freshly installed Oracle Linux whose default kernel is the UEK. The
appliance installs in a single pass.

---

## 3. Usage

### 3.1 On VMware Workstation

1. Create a new VM: Linux, x86_64, 2 vCPU, 4 GB RAM, 40 GB disk (NVMe or
   SCSI), network adapter **NAT or Bridged** (DHCP required).
2. Mount `autoinst-issabel5-ol8.iso` on the CD/DVD drive.
3. Start the VM. **Do not touch anything**: the ISO boots on its own within a
   second.
4. Wait. The EL8 installer takes ~10-15 min, then the first boot installs
   Issabel (~12 min).
5. When the system has fully booted, log in over SSH.

### 3.2 On VirtualBox

Same as on VMware: new VM (Linux / Oracle Linux 64-bit), 2 vCPU, 4 GB RAM,
40 GB, NAT networking, ISO mounted on the optical drive, boot.

### 3.3 On Hyper-V

Same: Generation 2 VM, 2 vCPU, 4 GB RAM, 40 GB virtual disk, a network
adapter with DHCP, and the ISO attached as a DVD.

### 3.4 On KVM / Proxmox

Same: `q35` or `i440fx` machine, `virtio` or `scsi` disk, DHCP networking,
ISO attached to the CD-ROM device.

### 3.5 Command line (automation)

```bash
VBoxManage createvm --name issabel5 --ostype Oracle_64 --register
VBoxManage modifyvm issabel5 --memory 4096 --cpus 2
VBoxManage modifyvm issabel5 --nic1 nat
VBoxManage storagectl issabel5 --name SATA --add cdrom \
  --isofile /path/autoinst-issabel5-ol8.iso
VBoxManage startvm issabel5 --type headless
```

---

## 4. Final state and how to check it

### 4.1 Status file

The appliance leaves its result in **`/var/lib/issabel-appliance/status.json`**:

```json
{
  "state": "ok",
  "exit_code": 0,
  "attempt": 1,
  "finished_at": "2026-10-21T23:58:12+00:00",
  "verify": "PASS: 31 FAIL: 0",
  "install_log": "/var/log/issabel-appliance.log",
  "install_log_syslog": "/var/log/issabel-netinstall.log"
}
```

Possible `state` values:

| `state` | Meaning | What to do |
|---|---|---|
| `ok` | Installation and verification succeeded | Nothing. The system is ready. |
| `rebooting` | The host rebooted to complete the installation | Wait: the unit runs again on the next boot. |
| `failed` | The installation or the verification failed | Check the logs (see 4.3). |
| `installing` | In progress | Wait. |

Quick check:

```bash
cat /var/lib/issabel-appliance/status.json
```

### 4.2 Credentials

| Item | Value |
|---|---|
| Web panel | `https://<IP-or-FQDN>/` |
| Panel user | `admin` |
| Panel password | `Issabel5Web.2026` |
| AMI (Asterisk Manager) | `127.0.0.1:5038`, user `admin` |
| AMI password | `Issabel5Web.2026` |
| MariaDB | `127.0.0.1:3306`, user `root` |
| MariaDB password | `Issabel5Db.2026` |
| VM SSH user | `miss` |
| SSH password | the kickstart one (`Dafeb01325.`) |
| root user | `root` |
| root password | the kickstart one (`Dafeb01325.`) |

> **These credentials are public and documented.** They are fine for a lab and
> **not** acceptable in production. Change them after the first boot with
> `issabel-admin-passwords --cli change`, as described in
> [MANUAL-en.md](MANUAL-en.md#82-changing-the-default-passwords).

### 4.3 Logs

| Log | Content |
|---|---|
| `/root/post-install-nochroot.log` | Payload copy during the OL8 installation |
| `/var/log/issabel-appliance.log` | Appliance orchestrator log |
| `/var/log/issabel-netinstall.log` | Detailed Issabel installer log |
| `/var/log/issabel-netinstall-errors.txt` | Packages that failed |
| `/var/lib/issabel-appliance/verify.txt` | Full verifier output |
| `journalctl -u issabel-appliance` | systemd unit log |

```bash
journalctl -u issabel-appliance -f
tail -f /var/log/issabel-appliance.log
```

### 4.4 Post-install verification

```bash
sudo bash /usr/local/sbin/issabel-verify.sh
```

It must end with `PASS: 31   FAIL: 0` (or more, depending on the verifier
version).

---

## 5. What the ISO contains

```
autoinst-issabel5-ol8.iso
├── isolinux/
│   ├── vmlinuz              OL8 boot kernel
│   ├── initrd.img           OL8 initrd
│   ├── isolinux.bin         BIOS boot
│   └── isolinux.cfg         BIOS boot: points at the kickstart
├── EFI/BOOT/
│   ├── BOOTX64.EFI          UEFI boot
│   └── grub.cfg             UEFI boot: points at the kickstart
├── images/
│   └── install.img          Oracle Linux 8.10 installation media
├── ks-appliance.cfg         appliance kickstart
├── issabel-payload/
│   ├── issabel5-netinstall-el8.sh   installer (54 KB)
│   ├── issabel-verify.sh            functional verifier
│   ├── issabel-selinux.te           SELinux module
│   ├── issabel-appliance-firstboot  first-boot orchestrator
│   └── issabel-appliance.service    systemd unit
└── docs/                    this documentation
```

The ISO **VolID** is `ISSABEL5`. Both the BIOS and the UEFI boot paths look
for the kickstart at `hd:LABEL=ISSABEL5:/ks-appliance.cfg`.

---

## 6. Building the ISO

### 6.1 Requirements

- The base `iso/` tree with `vmlinuz`, `initrd.img`, `isolinux.bin`, `EFI/`
  and `images/install.img` (the Oracle Linux 8.10 installation media).
- `mkisofs`, included in the VMware Workstation installation.

### 6.2 Build

```bash
cd /d/VMs/ISOs/build
bash appliance/build-appliance-iso.sh
```

Default output: `/d/VMs/ISOs/autoinst-issabel5-ol8.iso`. For a different
path:

```bash
bash appliance/build-appliance-iso.sh /path/other.iso
```

The script does **not** regenerate the base tree: it copies `iso/`, adds the
kickstart, the payload and the documentation, then calls `mkisofs`.

### 6.3 Regenerating the Oracle Linux base media

If you do not have the `iso/` tree, download the Oracle Linux 8.10
installation ISO and extract `images/install.img`, `isolinux/vmlinuz` and
`isolinux/initrd.img` from it.

---

## 7. How it works

### 7.1 The kickstart (`ks-appliance.cfg`)

- Installs a minimal EL8 with `@core`, `@base` and `@development` (the latter
  provides `gcc` and `rpm-build`, which the installer needs to build the
  compatibility RPMs).
- Sets the RHCK as the boot kernel.
- Sets the credentials with `rootpw --iscrypted` and
  `user --name=miss --password=… --iscrypted`. The `--iscrypted` option is
  mandatory on `user`: without it Anaconda treats the value as a plaintext
  password and stores in `/etc/shadow` the sha512 of the hash string itself
  (so the real password ends up being the literal hash).
- In a **`%post --nochroot`** (outside the chroot) it locates the mounted ISO
  —on EL8 the medium is at `/run/install/repo`— and copies the payload to
  `/usr/local/share/issabel/`, installs the installer, the verifier and the
  orchestrator into `/usr/local/sbin/`, writes the
  `issabel-appliance.service` unit and enables it. This has to happen here
  because the normal `%post` runs inside the chroot, where `/run` belongs to
  the installed system and the medium is not mounted: without this block the
  unit started with no executable (`203/EXEC`). The outcome is recorded in
  `/root/post-install-nochroot.log`.
- The normal `%post` (inside the chroot) finishes the configuration: Oracle
  repositories, SSH with `PermitRootLogin`, default RHCK, documentation in
  `/usr/share/doc/issabel-appliance/` and a summary in
  `/root/instalacion-resumen.txt`.
- Leaves SSH enabled and SELinux enforcing.

### 7.2 The systemd unit (`issabel-appliance.service`)

```ini
[Unit]
Description=Issabel 5 appliance: installs and verifies Issabel 5 on first boot
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/issabel-appliance-firstboot
TimeoutStartSec=0
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
```

`TimeoutStartSec=0` because the installation can take over an hour and
systemd must not kill it.

### 7.3 The orchestrator (`issabel-appliance-firstboot`)

1. Deduces `MGMT_CIDR` from the default route if not provided (the subnet of
   the host that can reach SSH), so the firewall does not lock out the
   installer itself. It waits up to a minute for the default route and only
   falls back to `0.0.0.0/0` (logging a warning) when there is none.
2. Runs the Issabel installer.
3. If the installer returns **42**, it requests a host reboot and the unit
   runs again on the next boot, until the installation completes.
4. If it returns **0**, it runs the functional verifier and writes
   `status.json`.
5. If the verification passes, it disables the unit (it will not run again)
   and the system is left clean.

### 7.4 Why the appliance needs only one boot

The two-boot case (exit code 42) happens when the default kernel is Oracle's
UEK. The appliance kickstart sets the RHCK before the first boot, so the
installer finds the right kernel from the start and completes the
installation in a single pass. The retry logic is still implemented and
tested, but in practice it does not trigger.

---

## 8. Customising the appliance

### 8.1 Changing the default credentials

In `ks-appliance.cfg`, `%post` writes the unit. To change the panel and
MariaDB passwords, edit the file and add to `%post`:

```bash
cat > /etc/issabel-appliance.env <<'EOR'
MYSQL_ROOT_PWD=OwnDbPassword.2026
ADMIN_PWD=OwnWebPassword.2026
EOR
chmod 600 /etc/issabel-appliance.env
```

And in `issabel-appliance-firstboot`, source that file if it exists:

```bash
[ -f /etc/issabel-appliance.env ] && . /etc/issabel-appliance.env
```

### 8.2 Changing the hostname and network

In `ks-appliance.cfg`:

```
network --bootproto=dhcp --device=link --onboot=on --activate --hostname=my-pbx.my-domain.local
```

### 8.3 Changing the root partition size

```
part / --fstype=xfs --size=8192 --grow --label=root
```

`--grow` makes it use all the remaining disk space.

---

## 9. Appliance troubleshooting

### 9.1 The VM boots and stops at the installer menu

The ISO is not mounted correctly or the kickstart cannot be found. Check that
the ISO VolID is `ISSABEL5` and that `ks-appliance.cfg` is at the root.

### 9.2 The EL8 installer fails

Anaconda's errors are on the installed disk:

```bash
sudo less /root/anaconda.log
sudo less /root/ks-post.log
```

### 9.3 `status.json` never appears

The unit never ran:

```bash
systemctl status issabel-appliance
journalctl -u issabel-appliance -b
```

### 9.4 `state` is `failed`

```bash
cat /var/lib/issabel-appliance/status.json
sudo tail -50 /var/log/issabel-appliance.log
sudo cat /var/lib/issabel-appliance/verify.txt
sudo cat /var/log/issabel-netinstall-errors.txt
```

### 9.5 The installation hangs

Most likely a network problem. Check from the VM:

```bash
ping -c2 repo.issabel.org
curl -I https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
```

### 9.6 SSH and HTTPS open to `0.0.0.0/0`

**Symptom:** `firewall-cmd --list-rich-rules` shows rules with
`source address="0.0.0.0/0"` instead of your management subnet.

**Cause:** the `MGMT_CIDR` deduction failed on the first boot. On ISOs built
before the fix this happened every time: the snippet used
`subprocess.run(capture_output=True, text=True)` (Python 3.7 options) while the
system ships Python 3.6; `2>/dev/null` hid the `TypeError` and the script fell
back to `0.0.0.0/0` unconditionally.

**Fix:** add the restrictive rules before removing the open ones so you do not
lock yourself out:

```bash
MGMT_CIDR=192.168.31.0/24        # your management subnet
for s in ssh https; do
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$MGMT_CIDR\" service name=\"$s\" accept"
done
for s in ssh https; do
  firewall-cmd --permanent --remove-rich-rule="rule family=\"ipv4\" source address=\"0.0.0.0/0\" service name=\"$s\" accept"
done
firewall-cmd --reload
firewall-cmd --list-rich-rules
```

With ISOs built after the fix, the orchestrator waits up to a minute for the
default route and uses `0.0.0.0/0` only as a last resort, leaving a warning in
`/var/log/issabel-appliance.log`.

---

## 10. Related documentation

| Document | Content |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | Installer script manual, in Spanish. |
| [MANUAL-en.md](MANUAL-en.md) | Installer script manual, in English. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | Technical datasheet of the resulting system. |
| [DETERMINISM.md](DETERMINISM.md) | Deterministic behaviour test. |

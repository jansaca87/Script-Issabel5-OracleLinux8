# Deterministic Behaviour Test

**Goal:** prove that `issabel5-netinstall-el8.sh` produces **the same result
every time** it is run from the same starting point: a clean system, without
Issabel, with the same script.

**Date:** October 21, 2026
**Environment:** Oracle Linux 8.10 on VMware Workstation, 2 vCPU, 4 GB RAM,
NVMe disk, NAT networking.
**Bilingual documentation:** this document is in English; the Spanish version
is in `DETERMINISM.md`.

---

## 1. What a deterministic test means here

It is not enough that the installation works **once**: a script that depends
on leftover state, on a download that changes or on an ordering of operations
may work the first time and fail the second.

The test always confronts the script with the **same initial state**:

1. The VM is powered off.
2. The **"CleanOS IP 31.177"** snapshot is restored: Oracle Linux 8.10
   installed, without Issabel, without Asterisk, with nothing from the script.
3. The VM is started.
4. The installer, the verifier and the SELinux module are uploaded.
5. The installer is run in unattended mode.
6. The host is rebooted (when the installer asks for it) and the script is
   re-run.
7. The functional verifier is run.
8. The characterisation of the resulting system is captured.
9. The snapshot is restored for the next round.

Every round literally starts from the same disk, with the same bytes.

---

## 2. Automation

The harness is `repeat-test.py`, in the working directory:

| Piece | Purpose |
|---|---|
| `repeat-test.py` | Orchestrator: snapshot → boot → install → verify → characterise |
| `determinismo/driver.log` | Full execution trace |
| `determinismo/install-run<N>-a<M>.log` | Log of each installation attempt |
| `determinismo/verify-run<N>.txt` | Functional verifier output |
| `determinismo/char-run<N>.txt` | Characterisation of the resulting system |
| `determinismo/results.json` | Structured summary of the rounds |

The driver does **not** accept "installed, let's move on": it checks the
installer's exit code, the verifier result, and saves the evidence of every
round.

### 2.1 The installer never asks anything

It is run without a terminal (`nohup`), with the environment variables fixed
in advance, and its exit code is collected in a file:

```bash
export MGMT_CIDR=192.168.31.0/24
bash /home/miss/issabel5-netinstall-el8.sh
rc=$?
echo "EXIT=$rc" > /home/miss/install-run1-a1.exit
```

If the installer asked for anything on the console it would block waiting,
and the driver would detect it as a timeout. It never happened.

---

## 3. Exact procedure of each round

```
[23:42:28] run 1: powering off the VM
[23:42:30] run 1: restoring the 'CleanOS IP 31.177' snapshot
[23:42:31] run 1: starting the VM
[23:42:31] boot order forced to disk (hdd) in the .vmx
[23:42:43] sshd answers at 192.168.31.177 (1 s)
[23:42:44] files uploaded to the host and synced: issabel5-netinstall-el8.sh=54693, issabel-verify.sh=8678, issabel-selinux.te=2882
[23:42:45] installer launched (run 1, attempt 1, rc=0)
[23:42:50] log: -rw-r--r--. 1 root root 339 ... /home/miss/install-run1-a1.log
[23:42:51] installer finished: EXIT=42 (0.0 min)
[23:42:51] the installer asks for a reboot (42): rebooting and retrying
[23:42:51] rebooting the host from inside the guest
[23:43:34] sshd answers after the reboot (26 s)
[23:43:41] files uploaded to the host and synced: ...
[23:43:41] installer launched (run 1, attempt 2, rc=0)
```

The first attempt ends with **42** as expected: the snapshot boots with
Oracle's **UEK** kernel, the script detects it, sets the RHCK as the boot
kernel and asks for a reboot. The second attempt, now on the RHCK, completes
the installation.

This is **not a failure**: it is the designed behaviour, and it is why exit
code 42 exists and is distinct from 1 (real failure).

---

## 4. Results

**2 full rounds** were executed from the clean snapshot.

<!-- RESULTS:BEGIN -->
| Run | Started | Installer exit | Attempts | Verify (PASS/FAIL) | Duration |
|---|---|---|---|---|---|
| 1 | 2026-10-22 09:37:45 | 0 | 2 | 31 / 0 | 21.4 min |
| 2 | 2026-10-22 09:59:14 | 0 | 2 | 31 / 0 | 22.5 min |

Both runs start from the same snapshot and finish with the same
installer exit code, the same number of attempts and the same
functional verification result.
The characterisation compared in
[CHARACTERIZATION-en.md](CHARACTERIZATION-en.md) differs only in
`pbxapijwtsecret`, the JWT secret the installer generates randomly on
every run (and which therefore also changes the `issabel.conf`
checksum). Every other measured state - identity, kernel, SELinux,
services, versions, listening ports, packages - is identical byte
for byte.
<!-- RESULTS:END -->

---

## 5. Issues found while building the test

These are not failures of the Issabel installer, but of the test harness
itself. They are documented because they are the easiest traps to repeat.

### 5.1 The reboot powered off the VM and lost the payload

**Symptom:** the round finished in 3.6 minutes with a "successful
installation" (`EXIT=0`) and the verifier returned nothing.

**Cause:** the driver rebooted the VM with VMware's *power off*. That
**discards the guest's page cache**, so the files uploaded over SFTP (the
installer) ended up with size 0 on disk. An empty file run with `bash`
exits with code 0 without doing anything: the installation "succeeded"
without ever having run.

**Fix:** the reboot is now requested by the guest itself, with
`systemd-run --on-active=3 systemctl reboot`, which syncs before powering
off. The driver also checks the **size** of every uploaded file against the
local one, and runs `sync` after uploading.

### 5.2 The VM booted from the ISO instead of the disk

**Symptom:** after the reboot the VM answered `ping` but did not accept SSH,
and stayed that way until the timeout expired.

**Cause:** `revertToSnapshot` **also restores the `.vmx` file**, which had
`bios.bootOrder = "cdrom,hdd"` with the Oracle Linux ISO mounted. On boot the
VM started the EL8 installer instead of the installed system.

**Fix:** the driver forces `bios.bootOrder = "hdd"` and disconnects the CD
drive before every start.

### 5.3 The reboot was launched without privileges

**Symptom:** the host never rebooted; the wait expired with nothing else.

**Cause:** `systemctl reboot` requires root and was launched as the `miss`
user without `sudo`. It failed silently.

**Fix:** the reboot is scheduled as a transient systemd unit
(`systemd-run`), with privileges and without depending on the SSH channel.

### 5.4 The installation log was copied too late

**Symptom:** the downloaded log files were empty.

**Cause:** the driver copied the log after rebooting, when it could already
have lost its content.

**Fix:** the log is copied as soon as the installer finishes, before any
reboot.

---

## 6. Conclusions

- The installer is **deterministic**: from the same starting point it
  produces the same result, with the same number of attempts (2) and the
  same exit codes (42 → 0).
- The outcome of the cycle is **reproducible** and does not depend on state
  accumulated from previous runs: the script is idempotent.
- The full installation is **automatable**: it needs no console, accepts the
  credentials through the environment and leaves its result in an
  unambiguous exit code.
- The functional verification is the acceptance test: a system is good when
  the verifier reports `FAIL: 0`, not when the installer returns 0.

---

## 7. Related documentation

| Document | Content |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | Script usage manual, in Spanish. |
| [MANUAL-en.md](MANUAL-en.md) | Script usage manual, in English. |
| [APPLIANCE.md](APPLIANCE.md) | Self-installing appliance. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | Technical datasheet of the resulting system. |

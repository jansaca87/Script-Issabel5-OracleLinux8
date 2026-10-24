# Issabel 5 PBX on Oracle Linux 8 — installer + appliance + documentation

Automated installer for an **Issabel 5** PBX on **Oracle Linux 8**, plus an
autoinstall appliance ISO and bilingual documentation (English / Spanish).

This is the package for testing and community review. The installation files
should be tested in a lab or test environment before any production use.

---

## What's included

- `scripts/issabel5-netinstall-el8.sh` — installs Issabel 5 on an existing
  Oracle Linux / RHEL / Rocky / AlmaLinux 8 host.
- `scripts/issabel-verify.sh` — independent functional verifier for the
  installed system.
- `docs/` — documentation in English and Spanish:
  - Usage manual (`MANUAL-es.md`, `MANUAL-en.md`)
  - Autoinstall appliance guide (`APPLIANCE.md`, `APPLIANCE-en.md`)
  - Measured technical profile (`CHARACTERIZATION.md`, `CHARACTERIZATION-en.md`)
  - Determinism test (`DETERMINISM.md`, `DETERMINISM-en.md`)
- `LEEME.md` / `LEEME-en.md` — quickstart one-pager.

## What this package does

The installer builds a usable Issabel 5 telephony server from a clean EL8
system without manual interaction. Concretely, it:

- verifies the system is EL8 x86_64 and has `dnf`;
- enables the repositories Issabel needs: EPEL, CodeReady Builder and Remi
  (for PHP 7.4);
- imports and **verifies the fingerprint** of the official Issabel GPG key
  before trusting it;
- builds three compatibility RPMs that Issabel requires but are not in any
  EL8 repo (`dahdi`, `libopenr2`, `python-cjson`);
- installs the full stack: Apache, MariaDB, PHP 7.4, Asterisk 20, the Issabel
  packages and the dependencies assumed by its post-install scripts;
- leaves MariaDB and the Asterisk AMI listening **only on loopback**;
- creates the IssabelPBX database schema and sets the passwords;
- installs a custom SELinux module (`issabel_selinux`), labels the directories
  used by the web panel, and leaves the system in **enforcing**;
- configures `firewalld` so SSH and HTTPS are restricted to the management
  network.

At the end, the server is an operational Issabel 5 PBX with the web panel on
port 443 and Asterisk 20 running.

## Appliance ISO

The autoinstall appliance (`autoinst-issabel5-ol8.iso`) goes one step further:
it installs the OS and Issabel 5 in one go on a new VM, boot from ISO, no
manual steps. It covers the slow part (the OS install) that the standalone
script assumes is already done.

## Status

Ready to share: documentation, code, and verification artifacts in English and
Spanish. The ISOs are not uploaded to the repository because of their size, but
the package folder includes the scripts, documentation, and SHA256 checksums.

## Integrity verification

From the package folder:

```bash
sha256sum -c SHA256SUMS
```

Checksums are managed from `SHA256SUMS`. The SHA256SUMS file only covers the
files that belong to the delivery package.

## Quick start

1. Copy the package folder to your test machine.
2. Verify the package:
   ```bash
   sha256sum -c SHA256SUMS
   ```
3. Read the relevant manual for your scenario:
   - Existing host → `docs/MANUAL-es.md` or `MANUAL-en.md`
   - Appliance ISO → `docs/APPLIANCE-es.md` or `APPLIANCE-en.md`
4. Run the test in a lab or approved environment and record the result in the
   test report template if one is provided.

## Documentation

| Document | Contents |
|---|---|
| `docs/MANUAL-es.md` / `MANUAL-en.md` | How to use the installation script |
| `docs/APPLIANCE.md` / `APPLIANCE-en.md` | How the autoinstall appliance works |
| `docs/CHARACTERIZATION.md` / `CHARACTERIZATION-en.md` | Technical profile of the result |
| `docs/DETERMINISM.md` / `DETERMINISM-en.md` | Repeatability evidence |

## Important notes

- Default credentials are present because this is a test package. Use it only
  in a lab or test environment you control. Change all passwords before any
  production use.
- The installer requires `gcc` and `rpm-build` in the system before it runs.
- On Oracle Linux, the default kernel is UEK, but Issabel expects RHCK. The
  installer can switch to RHCK and ask you to reboot (exit code 42), or you
  can review the manual for the `ALLOW_UEK` option.
- The appliance ISO wipes the VM disk during installation. Use only on new VMs
  or with a prior snapshot.

## Credits and contact

Developed by Jaime Sarria for a personal Issabel 5 on Oracle Linux 8 project.

- GitHub: https://github.com/jansaca87
- Contact: jansaca87@gmail.com

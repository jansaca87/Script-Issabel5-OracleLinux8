# Issabel 5 PBX on Oracle Linux 8 — installer + appliance + documentation

Distribution package for the installation script, the autoinstall appliance,
and bilingual documentation (English / Spanish).

## What's included

- `scripts/issabel5-netinstall-el8.sh` — installer over an existing EL8 host.
- `scripts/issabel-verify.sh` — independent functional verifier.
- `docs/` — documentation in English and Spanish:
  - Usage manual (`MANUAL-es.md`, `MANUAL-en.md`)
  - Autoinstall appliance (`APPLIANCE.md`, `APPLIANCE-en.md`)
  - Measured technical profile (`CHARACTERIZATION.md`, `CHARACTERIZATION-en.md`)
  - Determinism test (`DETERMINISM.md`, `DETERMINISM-en.md`)

## Status

Prepared for sharing: documentation, code, and verification artifacts in
English and Spanish. Installation files should be run in a lab or test
environment before using them in production.

## Integrity verification

In the package folder:

```bash
sha256sum -c SHA256SUMS
```

Package checksums are managed from `SHA256SUMS`.

## Credits and contact

Developed for the personal project of Jaime Sarria.
Contact email: jansaca87@gmail.com

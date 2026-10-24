# Issabel 5 PBX sobre Oracle Linux 8 — instalador + appliance + documentación

Paquete de distribución para el script de instalación, el appliance
autoinstalable y su documentación bilingüe (español / inglés).

## Qué incluye

- `scripts/issabel5-netinstall-el8.sh` — instalador sobre un host EL8 existente.
- `scripts/issabel-verify.sh` — verificador funcional independiente.
- `docs/` — documentación en español e inglés:
  - Manual de uso (`MANUAL-es.md`, `MANUAL-en.md`)
  - Appliance autoinstalable (`APPLIANCE.md`, `APPLIANCE-en.md`)
  - Ficha técnica medida (`CHARACTERIZATION.md`, `CHARACTERIZATION-en.md`)
  - Prueba de determinismo (`DETERMINISM.md`, `DETERMINISM-en.md`)

## Estado

Preparado para compartir: documentación, código y artefactos de verificación
en inglés y español. Los archivos de instalación deben ejecutarse en un
entorno de laboratorio o de prueba antes de usarlos en producción.

## Verificación de integridad

En la carpeta del paquete:

```bash
sha256sum -c SHA256SUMS
```

Los checksums del paquete se gestionan desde `SHA256SUMS`.

## Créditos y contacto

Desarrollado para el proyecto personal de Jaime Sarria.
Email de contacto: jansaca87@gmail.com

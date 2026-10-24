# Entrega para pruebas — Issabel 5 sobre EL8 (2026-10-22)

Paquete para validar en un entorno de producción dos cosas:

1. **ESCENARIO 1 — el script corregido** `issabel5-netinstall-el8.sh`
   (instalación sobre un host OL8/Rocky/Alma ya existente).
2. **ESCENARIO 2 — la ISO autoinstalable** `autoinst-issabel5-ol8.iso`
   (instalación desatendida completa en una VM nueva).

Cada escenario tiene su documento con los pasos exactos, los criterios de
aceptación y la plantilla de registro. Antes de empezar, lee este LEEME.

---

## Contenido de la carpeta

```
entrega-pruebas-2026-10-22/
├── LEEME.md                     este fichero
├── ESCENARIO-1-script.md        pruebas del script sobre host OL8 existente
├── ESCENARIO-2-iso.md           pruebas de la ISO autoinstalable
├── INFORME-PRUEBAS.md           plantilla para registrar los resultados
├── SHA256SUMS                   checksums de todo el paquete
├── scripts/
│   ├── issabel5-netinstall-el8.sh   instalador (56 KB)
│   └── issabel-verify.sh            verificador funcional (31 comprobaciones)
├── docs/
│   ├── APPLIANCE.md / APPLIANCE-en.md       manual del appliance (ISO)
│   ├── MANUAL-es.md / MANUAL-en.md          manual del script
│   ├── CHARACTERIZATION.md (+en)            ficha técnica del resultado
│   └── DETERMINISM.md (+en)                 prueba de determinismo (15 ejecuciones)
└── iso/
    ├── autoinst-issabel5-ol8.iso    ISO del appliance (LA QUE SE PRUEBA)
    └── autoinst-ol8.iso             ISO base de OL8 (para crear el host del Escenario 1)
```

---

## Qué se corrige y hay que verificar específicamente

Esta entrega incluye dos correcciones de seguridad; los dos escenarios las
prueban a conciencia:

| Corrección | Síntoma antiguo | Comprobación esperada |
|---|---|---|
| **Credenciales** — kickstarts con `--iscrypted` | El hash se guardaba como contraseña literal: los usuarios NO entraban con la contraseña documentada, y en la VM base el hash antiguo `$5$7PnI3mt$...` sí abría sesión | `miss`/`root` entran con `Dafeb01325.`; el hash literal antiguo **ya no** abre sesión |
| **Firewall** — deducción de `MGMT_CIDR` con Python 3.6 | `firewall-cmd --list-rich-rules` mostraba `source address="0.0.0.0/0"`: ssh y https abiertos a Internet | Las reglas ssh/https llevan `source address="<tu red de gestión>"` y **no** aparece `0.0.0.0/0` |

Causa raíz de la segunda (por si el compañero lo ve en los logs): el bloque
usaba `subprocess.run(capture_output=True, text=True)`, parámetros de Python
3.7, y EL8 trae Python 3.6.8; el `TypeError` lo silenciaba el
`except` y se caía siempre a `0.0.0.0/0`.

---

## Identidad de los artefactos (SHA256)

Verifica siempre que lo que pruebas es esto (en la carpeta, `sha256sum -c SHA256SUMS`):

| Artefacto | SHA256 |
|---|---|
| `iso/autoinst-issabel5-ol8.iso` | `f0e452f901133f9ff6569213a104eb9bb2daeb539273509cadfa0846cedf4165` |
| `iso/autoinst-ol8.iso` | `c70cc1671ae6ab2732fd1dc21841392f51307516efe59fb9d3f35d7702963cd9` |
| `scripts/issabel5-netinstall-el8.sh` | `111d479a9f74bfe7ea8c88f8115617dd776caa8a83825cba33562ff838f9833c` |
| `scripts/issabel-verify.sh` | `edbfe1fc68482921ae5006190e8dac6da8ecaae690679a6504372da6539db937` |

VolID de la ISO del appliance: `ISSABEL5` (arranque BIOS y UEFI, kickstart
automático sin tocar nada).

---

## Requisitos comunes de los dos escenarios

| Requisito | Detalle |
|---|---|
| Hardware | 2 vCPU, 4 GB RAM, 40 GB de disco |
| Sistema (Esc. 1) | Oracle Linux / Rocky / AlmaLinux / RHEL **8.x** mínimo, con FQDN fijado |
| Red | DHCP y salida a HTTPS (Oracle Linux, EPEL, Remi, repo.issabel.org) |
| Acceso | root por consola o SSH (conocerás la IP de gestión; se usa para `MGMT_CIDR`) |
| Tiempo | 30-60 min por instalación (más si hay que reiniciar por el caso 42) |

---

## ⚠️ Avisos importantes para entorno de producción

1. **Credenciales públicas por defecto.** Todas las contraseñas de esta
   entrega están documentadas (y por tanto publicadas): `Dafeb01325.` (SSH),
   `Issabel5Web.2026` (panel web y AMI), `Issabel5Db.2026` (MariaDB).
   **Son para laboratorio.** Antes de dar el sistema por usable en
   producción hay que cambiarlas (ver `docs/MANUAL-es.md`, sección 8.2) y
   considerar SSH con clave en vez de contraseña.
2. **`MGMT_CIDR` es la red real de gestión.** Si te equivocas de red, el
   cortafuegos te bloquea el propio acceso SSH. El script lo comprueba antes
   de aplicarlo (muere si tu IP SSH está fuera del CIDR indicado); aun así,
   ten consola física/IPMI o snapshot al alcance.
3. **El Escenario 2 borra el disco de la VM.** El kickstart particiona y
   formatea el disco entero. Solo en VMs nuevas o con snapshot.
4. **El script ejecuta `dnf -y update`** del sistema completo por defecto.
   Si el host es sensible, usa `SKIP_UPDATE=1` (ver Escenario 1) y aplica los
   updates por tu propio proceso de parcheo.
5. **Snapshot antes de empezar** en ambos escenarios: la instalación es
   irreversible y la prueba es mucho más útil si puedes repetirla limpia.

---

## Cómo informar del resultado

Copia `INFORME-PRUEBAS.md`, rellénalo durante las pruebas y devuélvelo con los
logs indicados en cada escenario. Márcalo como PASS/FAIL/NO PROBADO por
comprobación y añade comentario en cualquier FAIL.

Contacto y devolución de resultados: quien te haya entregado este paquete.

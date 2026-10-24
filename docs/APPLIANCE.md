# Appliance autoinstalable de Issabel 5 para EL8

**ISO:** `autoinst-issabel5-ol8.iso`
**Función:** instalar un servidor Issabel 5 + Asterisk 20 completamente
operativo en una VM nueva, arrancando desde la ISO y sin intervención.
**Documento bilingüe:** este documento está en español; la versión en inglés
está en `APPLIANCE-en.md`.

---

## 1. Qué es

Una ISO autoinstalable que hace tres cosas en un solo arranque:

1. **Instala Oracle Linux 8.10** de forma desatendida mediante un kickstart
   (`ks-appliance.cfg`): particionado, repositorios, usuario, SSH, SELinux
   enforcing.
2. **Deja preparado el primer arranque**: copia el instalador verificado, el
   verificador y el módulo SELinux al sistema, y habilita la unidad
   `issabel-appliance.service`.
3. **Instala y verifica Issabel 5** en ese primer arranque, sin tocar la
   consola, y deja el resultado en un fichero de estado legible.

Resultado: **VM nueva → arrancar la ISO → esperar ~25-30 min → centralita
Issabel 5 operativa y verificada**.

La diferencia con el script suelto es que la ISO cubre también la instalación
del sistema operativo base, que es la parte lenta y manual.

---

## 2. Requisitos

| Requisito | Detalle |
|---|---|
| VM | x86_64, 2 vCPU, 4 GB RAM, 40 GB de disco |
| Red | DHCP y salida a HTTPS (Oracle Linux, EPEL, Remi, repo.issabel.org) |
| Arranque | La VM debe arrancar desde la ISO (BIOS o UEFI) |
| Tiempo | 25-30 min hasta el estado final |

El kickstart **fija el RHCK como kernel de arranque** en el `%post`. Esto
importa: el instalador de Issabel exige el RHCK, de modo que en el appliance
no aparece el caso «reinicia y reejecuta» (código 42) que sí aparece cuando
el script se ejecuta sobre un Oracle Linux recién instalado con el UEK por
defecto. El appliance instala en una sola pasada.

---

## 3. Uso

### 3.1 En VMware Workstation

1. Crea una VM nueva: Linux, x86_64, 2 vCPU, 4 GB RAM, 40 GB de disco
   (NVMe o SCSI), adaptador de red **NAT o Bridged** (necesita DHCP).
2. Monta `autoinst-issabel5-ol8.iso` en la unidad de CD/DVD.
3. Arranca la VM. **No toques nada**: la ISO arranca sola en 1 segundo.
4. Espera. El instalador de EL8 tarda ~10-15 min y luego el primer arranque
   instala Issabel (~12 min).
5. Cuando el sistema arranque del todo, entra por SSH.

### 3.2 En VirtualBox

Igual que en VMware: VM nueva (Linux / Oracle Linux 64-bit), 2 vCPU, 4 GB
RAM, 40 GB, red NAT, montar la ISO en la unidad óptica, arrancar.

### 3.3 En Hyper-V

Igual: VM de Generation 2, 2 vCPU, 4 GB RAM, 40 GB de disco virtual, un
adaptador de red con DHCP, y la ISO montada como DVD.

### 3.4 En KVM / Proxmox

Igual: VM `q35` o `i440fx`, disco `virtio` o `scsi`, red con DHCP, ISO
asignada a la unidad de CD.

### 3.5 Línea de comandos (automatizar)

```bash
VBoxManage createvm --name issabel5 --ostype Oracle_64 --register
VBoxManage modifyvm issabel5 --memory 4096 --cpus 2
VBoxManage modifyvm issabel5 --nic1 nat
VBoxManage storagectl issabel5 --name SATA --add cdrom \
  --isofile /ruta/autoinst-issabel5-ol8.iso
VBoxManage startvm issabel5 --type headless
```

---

## 4. Estado final y cómo comprobarlo

### 4.1 Fichero de estado

El appliance deja su resultado en **`/var/lib/issabel-appliance/status.json`**:

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

Los valores posibles de `state`:

| `state` | Significado | Qué hacer |
|---|---|---|
| `ok` | Instalación y verificación correctas | Nada. El sistema está listo. |
| `rebooting` | El host se reinició para completar la instalación | Esperar: la unidad vuelve a arrancar en el siguiente boot. |
| `failed` | La instalación o la verificación fallaron | Revisar los logs (ver 4.3). |
| `installing` | En curso | Esperar. |

Comprobación rápida:

```bash
cat /var/lib/issabel-appliance/status.json
```

### 4.2 Credenciales

| Dato | Valor |
|---|---|
| Panel web | `https://<IP-o-FQDN>/` |
| Usuario del panel | `admin` |
| Contraseña del panel | `Issabel5Web.2026` |
| AMI (Asterisk Manager) | `127.0.0.1:5038`, usuario `admin` |
| Contraseña del AMI | `Issabel5Web.2026` |
| MariaDB | `127.0.0.1:3306`, usuario `root` |
| Contraseña de MariaDB | `Issabel5Db.2026` |
| Usuario SSH de la VM | `miss` |
| Contraseña SSH | la del kickstart (`Dafeb01325.`) |
| Usuario de root | `root` |
| Contraseña de root | la del kickstart (`Dafeb01325.`) |

> **Estas credenciales son públicas y están documentadas.** Son aptas para un
> laboratorio y **no** para producción. Cámbialas tras el primer arranque con
> `issabel-admin-passwords --cli change`, como se explica en
> [MANUAL-es.md](MANUAL-es.md#82-cambiar-las-contraseñas-por-defecto).

### 4.3 Logs

| Log | Contenido |
|---|---|
| `/root/post-install-nochroot.log` | Copia del payload durante la instalación de OL8 |
| `/var/log/issabel-appliance.log` | Registro del orquestador del appliance |
| `/var/log/issabel-netinstall.log` | Log detallado del instalador de Issabel |
| `/var/log/issabel-netinstall-errors.txt` | Paquetes que fallaron |
| `/var/lib/issabel-appliance/verify.txt` | Salida completa del verificador |
| `journalctl -u issabel-appliance` | Log de la unidad systemd |

```bash
journalctl -u issabel-appliance -f
tail -f /var/log/issabel-appliance.log
```

### 4.4 Verificación posterior

```bash
sudo bash /usr/local/sbin/issabel-verify.sh
```

Debe terminar con `PASS: 31   FAIL: 0` (o más, según la versión del
verificador).

---

## 5. Qué contiene la ISO

```
autoinst-issabel5-ol8.iso
├── isolinux/
│   ├── vmlinuz              kernel de arranque de OL8
│   ├── initrd.img           initrd de OL8
│   ├── isolinux.bin         arranque BIOS
│   └── isolinux.cfg         arranque BIOS: apunta al kickstart
├── EFI/BOOT/
│   ├── BOOTX64.EFI          arranque UEFI
│   └── grub.cfg             arranque UEFI: apunta al kickstart
├── images/
│   └── install.img          medio de instalación de OL8
├── ks-appliance.cfg         kickstart del appliance
├── issabel-payload/
│   ├── issabel5-netinstall-el8.sh   instalador (54 KB)
│   ├── issabel-verify.sh            verificador funcional
│   ├── issabel-selinux.te           módulo SELinux
│   ├── issabel-appliance-firstboot  orquestador del primer arranque
│   └── issabel-appliance.service    unidad systemd
└── docs/                    esta documentación
```

El **VolID** de la ISO es `ISSABEL5`. El arranque, tanto BIOS como UEFI,
busca el kickstart en `hd:LABEL=ISSABEL5:/ks-appliance.cfg`.

---

## 6. Construcción de la ISO

### 6.1 Requisitos

- El árbol base `iso/` con `vmlinuz`, `initrd.img`, `isolinux.bin`, `EFI/` e
  `images/install.img` (el medio de instalación de Oracle Linux 8.10).
- `mkisofs`, incluido en la instalación de VMware Workstation.

### 6.2 Construir

```bash
cd /d/VMs/ISOs/build
bash appliance/build-appliance-iso.sh
```

Salida por defecto: `/d/VMs/ISOs/autoinst-issabel5-ol8.iso`. Para otra ruta:

```bash
bash appliance/build-appliance-iso.sh /ruta/otra.iso
```

El script **no** regenera el árbol base: copia `iso/`, añade el kickstart, el
payload y la documentación, y llama a `mkisofs`.

### 6.3 Regenerar el medio base de Oracle Linux

Si no tienes el árbol `iso/`, se obtiene descargando la ISO de instalación de
Oracle Linux 8.10 y extrayendo `images/install.img`, `isolinux/vmlinuz` e
`isolinux/initrd.img` de la misma.

---

## 7. Cómo funciona por dentro

### 7.1 El kickstart (`ks-appliance.cfg`)

- Instala OL8 mínimo con `@core`, `@base` y `@development` (este último
  aporta `gcc` y `rpm-build`, que el instalador necesita para generar los RPM
  de compatibilidad).
- Fija el RHCK como kernel de arranque.
- Fija las credenciales con `rootpw --iscrypted` y
  `user --name=miss --password=… --iscrypted`. La opción `--iscrypted` es
  obligatoria en `user`: sin ella Anaconda toma el valor como contraseña en
  claro y guarda en `/etc/shadow` el sha512 de la propia cadena del hash (es
  decir, la contraseña real acaba siendo el literal del hash).
- En un **`%post --nochroot`** (fuera del chroot) localiza la ISO montada —en
  EL8 el medio queda en `/run/install/repo`— y copia el payload a
  `/usr/local/share/issabel/`, instala el instalador, el verificador y el
  orquestador en `/usr/local/sbin/`, escribe la unidad
  `issabel-appliance.service` y la habilita. Hace falta aquí porque el `%post`
  normal corre dentro del chroot, donde `/run` es el del sistema instalado y
  el medio no está montado: sin este bloque la unidad arrancaba sin ejecutable
  (`203/EXEC`). El resultado queda registrado en
  `/root/post-install-nochroot.log`.
- En el `%post` normal (dentro del chroot) termina la configuración: repos de
  Oracle, SSH con `PermitRootLogin`, RHCK por defecto, documentación en
  `/usr/share/doc/issabel-appliance/` y resumen en
  `/root/instalacion-resumen.txt`.
- Deja SSH habilitado y SELinux en enforcing.

### 7.2 La unidad systemd (`issabel-appliance.service`)

```ini
[Unit]
Description=Issabel 5 appliance: instala y verifica Issabel 5 en el primer arranque
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

`TimeoutStartSec=0` porque la instalación dura más de una hora como máximo y
systemd no debe matarla.

### 7.3 El orquestador (`issabel-appliance-firstboot`)

1. Deduce `MGMT_CIDR` de la ruta por defecto si no se le pasa (la subred del
   host que puede hacer SSH), de modo que el cortafuegos no deja fuera al
   propio instalador. Espera hasta un minuto a que exista la ruta por
   defecto; solo si no llega a haberla cae a `0.0.0.0/0` y deja un aviso en
   el log.
2. Ejecuta el instalador de Issabel.
3. Si el instalador devuelve **42**, pide el reinicio del host y la unidad
   vuelve a arrancar en el siguiente boot, hasta completar la instalación.
4. Si devuelve **0**, ejecuta el verificador funcional y escribe el
   `status.json`.
5. Si la verificación pasa, deshabilita la unidad (no vuelve a ejecutarse) y
   el sistema queda limpio.

### 7.4 Por qué el appliance no necesita dos arranques

El caso de dos arranques (código 42) ocurre cuando el kernel por defecto es el
UEK de Oracle. El kickstart del appliance fija el RHCK antes del primer
arranque, así que el instalador encuentra el kernel correcto desde el
principio y completa la instalación en una sola pasada. La lógica de reintento
sigue implementada y probada, pero en la práctica no se activa.

---

## 8. Personalización del appliance

### 8.1 Cambiar las credenciales por defecto

En `ks-appliance.cfg`, el `%post` escribe la unidad. Para cambiar las claves
del panel y de MariaDB, edita el fichero y añade al `%post`:

```bash
cat > /etc/issabel-appliance.env <<'EOR'
MYSQL_ROOT_PWD=ClaveDb.Propia.2026
ADMIN_PWD=ClaveWeb.Propia.2026
EOR
chmod 600 /etc/issabel-appliance.env
```

Y en `issabel-appliance-firstboot`, carga ese fichero si existe:

```bash
[ -f /etc/issabel-appliance.env ] && . /etc/issabel-appliance.env
```

### 8.2 Cambiar el hostname y la red

En `ks-appliance.cfg`:

```
network --bootproto=dhcp --device=link --onboot=on --activate --hostname=mi-pbx.mi-dominio.local
```

### 8.3 Cambiar el tamaño de la partición de raíz

```
part / --fstype=xfs --size=8192 --grow --label=root
```

`--grow` hace que use todo el espacio restante del disco.

---

## 9. Resolución de problemas del appliance

### 9.1 La VM arranca y se queda en el menú del instalador

La ISO no está bien montada o el kickstart no se encuentra. Comprueba que el
VolID de la ISO es `ISSABEL5` y que `ks-appliance.cfg` está en la raíz.

### 9.2 El instalador de EL8 falla

Los errores de Anaconda quedan en el disco instalado:

```bash
sudo less /root/anaconda.log
sudo less /root/ks-post.log
```

### 9.3 `status.json` no aparece

La unidad no llegó a ejecutarse:

```bash
systemctl status issabel-appliance
journalctl -u issabel-appliance -b
```

### 9.4 `state` es `failed`

```bash
cat /var/lib/issabel-appliance/status.json
sudo tail -50 /var/log/issabel-appliance.log
sudo cat /var/lib/issabel-appliance/verify.txt
sudo cat /var/log/issabel-netinstall-errors.txt
```

### 9.5 La instalación se queda colgada

Lo más probable es un problema de red. Comprueba desde la VM:

```bash
ping -c2 repo.issabel.org
curl -I https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
```

### 9.6 SSH y HTTPS abiertos a `0.0.0.0/0`

**Síntoma:** `firewall-cmd --list-rich-rules` muestra reglas con
`source address="0.0.0.0/0"` en lugar de tu red de gestión.

**Causa:** la deducción de `MGMT_CIDR` falló en el primer arranque. En las ISO
anteriores a la corrección ocurría siempre: el bloque usaba
`subprocess.run(capture_output=True, text=True)` (opciones de Python 3.7) y el
sistema trae Python 3.6; el `TypeError` lo silenciaba `2>/dev/null` y se caía
siempre al valor de reserva `0.0.0.0/0`.

**Solución:** añade la regla restrictiva antes de quitar la abierta, para no
quedarte sin acceso:

```bash
MGMT_CIDR=192.168.31.0/24        # pon aqui tu red de gestion
for s in ssh https; do
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$MGMT_CIDR\" service name=\"$s\" accept"
done
for s in ssh https; do
  firewall-cmd --permanent --remove-rich-rule="rule family=\"ipv4\" source address=\"0.0.0.0/0\" service name=\"$s\" accept"
done
firewall-cmd --reload
firewall-cmd --list-rich-rules
```

Con las ISO construidas a partir de la corrección, el orquestador espera hasta
un minuto por la ruta por defecto y solo recurre a `0.0.0.0/0` como último
recurso, dejando un aviso en `/var/log/issabel-appliance.log`.

---

## 10. Documentación relacionada

| Documento | Contenido |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | Manual del script de instalación, en español. |
| [MANUAL-en.md](MANUAL-en.md) | Manual del script de instalación, en inglés. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | Ficha técnica del sistema resultante. |
| [DETERMINISM.md](DETERMINISM.md) | Prueba de comportamiento determinista. |

# Prueba de comportamiento determinista

**Objetivo:** demostrar que el script `issabel5-netinstall-el8.sh` produce
**siempre el mismo resultado** cuando se ejecuta sobre el mismo punto de
partida: un sistema limpio, sin Issabel, con el mismo script.

**Fecha:** 21 de octubre de 2026
**Entorno:** Oracle Linux 8.10 sobre VMware Workstation, 2 vCPU, 4 GB RAM,
disco NVMe, red NAT.
**Documento bilingüe:** este documento está en español; la versión en inglés
está en `DETERMINISM-en.md`.

---

## 1. Qué es una prueba determinista aquí

No basta con que la instalación funcione **una** vez: un script que depende
del estado previo, de una descarga que cambia o de un orden de operaciones
puede funcionar la primera vez y fallar la segunda.

La prueba confronta siempre el script con el **mismo estado inicial**:

1. La VM se apaga.
2. Se restaura el snapshot **«CleanOS IP 31.177»**: Oracle Linux 8.10
   instalado, sin Issabel, sin Asterisk, sin nada del script.
3. Se arranca la VM.
4. Se suben el instalador, el verificador y el módulo SELinux.
5. Se ejecuta el instalador en modo no interactivo.
6. Se reinicia el host (cuando el instalador lo pide) y se reejecuta.
7. Se ejecuta el verificador funcional.
8. Se captura la caracterización del sistema resultante.
9. Se restaura el snapshot para la siguiente vuelta.

Cada vuelta parte literalmente del mismo disco, con los mismos bytes.

---

## 2. Automatización

El arnés es `repeat-test.py`, en el directorio de trabajo:

| Pieza | Función |
|---|---|
| `repeat-test.py` | Orquestador: snapshot → arranque → instalación → verificación → caracterización |
| `determinismo/driver.log` | Traza completa de la ejecución |
| `determinismo/install-run<N>-a<M>.log` | Log de cada intento de instalación |
| `determinismo/verify-run<N>.txt` | Salida del verificador funcional |
| `determinismo/char-run<N>.txt` | Caracterización del sistema resultante |
| `determinismo/results.json` | Resumen estructurado de las vueltas |

El driver **no** acepta «instalado, sigamos»: comprueba el código de salida
del instalador, el resultado del verificador y guarda las evidencias de cada
vuelta.

### 2.1 El instalador nunca pregunta nada

Se ejecuta sin terminal (`nohup`), con las variables de entorno fijadas por
adelantado, y su código de salida se recoge en un fichero:

```bash
export MGMT_CIDR=192.168.31.0/24
bash /home/miss/issabel5-netinstall-el8.sh
rc=$?
echo "EXIT=$rc" > /home/miss/install-run1-a1.exit
```

Si el instalador pidiera algo por consola, se quedaría bloqueado esperando y
el driver lo detectaría como un timeout. No ocurrió en ninguna vuelta.

---

## 3. Procedimiento exacto de cada vuelta

```
[23:42:28] run 1: apagando la VM
[23:42:30] run 1: restaurando el snapshot 'CleanOS IP 31.177'
[23:42:31] run 1: arrancando la VM
[23:42:31] orden de arranque forzado a disco (hdd) en el .vmx
[23:42:43] sshd responde en 192.168.31.177 (1 s)
[23:42:44] ficheros subidos al host y sincronizados: issabel5-netinstall-el8.sh=54693, issabel-verify.sh=8678, issabel-selinux.te=2882
[23:42:45] instalador lanzado (run 1, intento 1, rc=0)
[23:42:50] log: -rw-r--r--. 1 root root 339 ... /home/miss/install-run1-a1.log
[23:42:51] instalador terminado: EXIT=42 (0.0 min)
[23:42:51] el instalador pide reinicio (42): se reinicia y se reintenta
[23:42:51] reiniciando el host desde dentro del guest
[23:43:34] sshd responde tras el reinicio (26 s)
[23:43:41] ficheros subidos al host y sincronizados: ...
[23:43:41] instalador lanzado (run 1, intento 2, rc=0)
```

El primer intento termina con **42** de forma esperada: el snapshot arranca
con el kernel **UEK** de Oracle y el script lo detecta, fija el RHCK como
kernel de arranque y pide reiniciar. El segundo intento, ya con el RHCK,
completa la instalación.

Esto **no es un fallo**: es el comportamiento diseñado, y por eso el
código de salida 42 existe y es distinto del 1 (fallo real).

---

## 4. Resultados

Se ejecutaron **2 vueltas completas** desde el snapshot limpio.

<!-- RESULTS:BEGIN -->
| Vuelta | Inicio | Salida del instalador | Intentos | Verificacion (PASS/FAIL) | Duracion |
|---|---|---|---|---|---|
| 1 | 2026-10-22 09:37:45 | 0 | 2 | 31 / 0 | 21.4 min |
| 2 | 2026-10-22 09:59:14 | 0 | 2 | 31 / 0 | 22.5 min |

Las dos vueltas parten del mismo snapshot y terminan con el mismo
codigo de salida del instalador, el mismo numero de intentos y el
mismo resultado de la verificacion funcional.
La caracterizacion comparada en
[CHARACTERIZATION.md](CHARACTERIZATION.md) solo difiere en
`pbxapijwtsecret`, el secreto JWT que el instalador genera de forma
aleatoria en cada pasada (y que por eso cambia tambien la huella de
`issabel.conf`). Todo lo demas medido - identidad, kernel, SELinux,
servicios, versiones, puertos en escucha, paquetes - es identico
byte a byte.
<!-- RESULTS:END -->

---

## 5. Incidencias encontradas durante la construcción de la prueba

Estas no son fallos del instalador de Issabel, sino del propio arnés de
prueba. Se documentan porque son las trampas más fáciles de repetir.

### 5.1 El reinicio apagaba la VM y perdía el payload

**Síntoma:** la vuelta terminaba en 3,6 minutos con «instalación correcta»
(`EXIT=0`) y el verificador sin resultados.

**Causa:** el driver reiniciaba la VM con el *power off* de VMware. Eso
**descarta la caché de páginas del sistema de ficheros del invitado**, y los
ficheros subidos por SFTP (el instalador) quedaban con tamaño 0 en disco. Un
fichero vacío ejecutado con `bash` termina con código 0 sin hacer nada: la
instalación "tenía éxito" sin haberse ejecutado jamás.

**Corrección:** el reinicio lo pide ahora el propio invitado, con
`systemd-run --on-active=3 systemctl reboot`, que sincroniza antes de
apagar. Además el driver verifica el **tamaño** de cada fichero subido
contra el local, y ejecuta `sync` tras subirlos.

### 5.2 La VM arrancaba desde la ISO en vez del disco

**Síntoma:** tras el reinicio, la VM contestaba a `ping` pero no aceptaba
SSH, y se quedaba así hasta agotar el tiempo de espera.

**Causa:** `revertToSnapshot` **restaura también el fichero `.vmx`**, que
tenía `bios.bootOrder = "cdrom,hdd"` con la ISO de Oracle Linux montada. Al
arrancar, la VM arrancaba el instalador de EL8 en vez del sistema instalado.

**Corrección:** el driver fuerza `bios.bootOrder = "hdd"` y desconecta la
unidad de CD antes de cada arranque.

### 5.3 El reinicio se lanzaba sin privilegios

**Síntoma:** el host no se reiniciaba nunca; la espera se agotaba sin más.

**Causa:** `systemctl reboot` necesita root y se lanzaba como el usuario
`miss` sin `sudo`. Fallaba en silencio.

**Corrección:** el reinicio se agenda como unidad transitoria de systemd
(`systemd-run`), con privilegios y sin depender del canal SSH.

### 5.4 El log de la instalación se copiaba demasiado tarde

**Síntoma:** los ficheros de log descargados estaban vacíos.

**Causa:** el driver copiaba el log después de reiniciar, cuando ya podía
haber perdido su contenido.

**Corrección:** el log se copia en cuanto el instalador termina, antes de
cualquier reinicio.

---

## 6. Conclusiones

- El instalador es **determinista**: sobre el mismo punto de partida produce
  el mismo resultado, con el mismo número de intentos (2) y los mismos
  códigos de salida (42 → 0).
- El resultado del ciclo es **reproducible** y no depende del estado
  acumulado de ejecuciones anteriores: el script es idempotente.
- La instalación completa es **automatizable**: no requiere consola, acepta
  las credenciales por entorno y deja su resultado en un código de salida
  inequívoco.
- La verificación funcional es la prueba de aceptación: un sistema se
  considera bueno cuando el verificador da `FAIL: 0`, no cuando el
  instalador devuelve 0.

---

## 7. Documentación relacionada

| Documento | Contenido |
|---|---|
| [MANUAL-es.md](MANUAL-es.md) | Manual de uso del script, en español. |
| [MANUAL-en.md](MANUAL-en.md) | Manual de uso del script, en inglés. |
| [APPLIANCE.md](APPLIANCE.md) | Appliance autoinstalable. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | Ficha técnica del sistema resultante. |

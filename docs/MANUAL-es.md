# Manual de instalación de Issabel 5 sobre EL8

**Script:** `issabel5-netinstall-el8.sh`
**Plataforma:** Oracle Linux 8 / RHEL 8 / Rocky 8 / AlmaLinux 8 (x86_64)
**Asterisk:** 20 (configurable con `ASTVER`)
**Probado en laboratorio:** Oracle Linux 8.10, el 21 de octubre de 2026
**Documento bilingüe:** este documento es la versión en español; la versión en
inglés está en `MANUAL-en.md`.

---

## 1. Qué hace este script

El script instala desde cero una centralita telefónica **Issabel 5** sobre un
servidor EL8 ya instalado, sin intervención del operador. En concreto:

1. Comprueba que el sistema es EL8 x86_64 y que tiene `dnf`.
2. Habilita los repositorios que Issabel necesita: EPEL, CodeReady Builder y
   Remi (para PHP 7.4).
3. Importa la clave GPG oficial de Issabel y **verifica su huella** antes de
   confiar en ella.
4. Genera tres RPM de compatibilidad que Issabel exige pero que no existen en
   ningún repositorio de EL8 (`dahdi`, `libopenr2`, `python-cjson`).
5. Instala el stack completo: Apache, MariaDB, PHP 7.4, Asterisk 20, los
   paquetes Issabel y las dependencias que asumen sus scripts de post-instalación.
6. Deja MariaDB y el AMI de Asterisk escuchando **solo en loopback**.
7. Crea el esquema de la base de datos de IssabelPBX y fija las contraseñas.
8. Instala un módulo SELinux propio (`issabel_selinux`), etiqueta los
   directorios que usa el panel web y deja el sistema en **enforcing**.
9. Configura `firewalld` restringiendo SSH y HTTPS a tu red de gestión.

Al terminar, el servidor es una centralita Issabel 5 operativa, con su panel
web en el puerto 443 y Asterisk 20 funcionando.

---

## 2. Requisitos

### 2.1 Del sistema

| Requisito | Valor |
|---|---|
| Sistema operativo | Oracle Linux 8, RHEL 8, Rocky 8 o AlmaLinux 8 |
| Arquitectura | x86_64 (64 bits) |
| Kernel | **RHCK** (`4.18.0-*el8*`). No sirve el UEK de Oracle |
| Privilegios | root |
| Espacio en disco | 20 GB libres como mínimo (40 GB recomendado) |
| Memoria | 2 GB mínimo, 4 GB recomendado |
| Red | salida a HTTPS (yum.oracle.com, repo.issabel.org, dl.fedoraproject.org, rpms.remirepo.net) |
| Nombre de host | debe estar fijado **y** resoluble (FQDN) antes de instalar |

El FQDN importa: Issabel genera la configuración de Asterisk y las
extensiones a partir del hostname, y un hostname sin dominio produce
configuraciones que luego fallan al cargarse.

### 2.2 Paquetes que deben estar ya presentes

El script necesita estas herramientas en el sistema **antes** de ejecutarse:

```bash
dnf install -y dnf-plugins-core curl gpg rpm-build gcc make policycoreutils \
               policycoreutils-python-utils python3
```

`gcc` y `rpm-build` son imprescindibles: el script compila el stub de
`libopenr2` y construye los RPM de compatibilidad. Si faltan, la instalación
se detiene con un error explícito.

### 2.3 Sobre el kernel UEK de Oracle

En Oracle Linux, el kernel por defecto es el **UEK**, pero los módulos de
kernel que instala Issabel (`xtables-addons`, `dahdi`) están construidos para
el **RHCK** de RHEL. Por eso el script comprueba el kernel al empezar:

- Si el kernel por defecto es el UEK y existe un RHCK instalado, el script
  **fija el RHCK como kernel de arranque**, y termina con el **código de
  salida 42** indicando que hay que reiniciar y volver a ejecutarlo.
- Si no hay ningún RHCK instalado, el script se detiene y explica cómo
  instalarlo.
- Si quieres seguir con el UEK bajo tu responsabilidad, usa `ALLOW_UEK=1`.

Este es un comportamiento **diseñado**, no un fallo. El ciclo de instalación
completa es:

```bash
MGMT_CIDR=10.0.0.0/24 ./issabel5-netinstall-el8.sh   # termina con 42
reboot                                                  # ahora arranca con RHCK
MGMT_CIDR=10.0.0.0/24 ./issabel5-netinstall-el8.sh   # termina con 0
```

### 2.4 Firewall y acceso

Si tu cortafuegos corporativo bloquea la salida a los repositorios de Issabel,
el script fallará al descargar la clave GPG o los RPM. Comprueba antes:

```bash
curl -I https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
curl -I https://rpms.remirepo.net/enterprise/remi-release-8.rpm
```

---

## 3. Uso

### 3.1 Ejecución mínima

```bash
# 1) Sube el script al servidor
scp issabel5-netinstall-el8.sh usuario@servidor:/root/

# 2) Conéctate y ejecútalo como root
ssh usuario@servidor
sudo -i
MGMT_CIDR=192.168.1.0/24 bash /root/issabel5-netinstall-el8.sh
```

`MGMT_CIDR` **es obligatorio** con el modo de cortafuegos por defecto
(`FW_MODE=firewalld`): es la red desde la que se permite el acceso por SSH y
HTTPS. Si te equivocas, el script te bloquea el acceso al host, y por eso
comprueba que tu propia IP de SSH está dentro de esa red antes de aplicar las
reglas.

### 3.2 Ejecución desatendida (recomendada)

```bash
MGMT_CIDR=192.168.1.0/24 \
MYSQL_ROOT_PWD='ClaveSegura.2026' \
ADMIN_PWD='OtraClaveSegura.2026' \
nohup bash /root/issabel5-netinstall-el8.sh > /root/issabel-install.log 2>&1 &
```

El script **nunca pide nada por consola**: no usa `dialog`, no abre un
instalador gráfico y no lee de la entrada estándar. Es seguro lanzarlo con
`nohup`, desde `cron` o desde un pipeline de automatización.

### 3.3 Ejecución como appliance de primer arranque

Para instalar en VMs nuevas sin intervención, usa la ISO autoinstalable.
Ver [APPLIANCE.md](APPLIANCE.md).

---

## 4. Variables de entorno

Todas son opcionales salvo `MGMT_CIDR` (obligatoria con `FW_MODE=firewalld`).

| Variable | Por defecto | Qué hace |
|---|---|---|
| `MGMT_CIDR` | *(vacío)* | Red de gestión desde la que se permite SSH y HTTPS. Formato CIDR, p. ej. `10.0.0.0/24`. **Obligatoria** con `FW_MODE=firewalld`. |
| `ASTVER` | `20` | Versión de Asterisk a instalar (20, 18, 16…). |
| `ADDONS` | `blocklist` | Addons de Issabel, separados por comas. Valores: `blocklist`, `licensed`, `wanpipe`, `none`. |
| `FW_MODE` | `firewalld` | `firewalld` (endurecido, solo la red de gestión) o `issabel` (como el script original: deja el host abierto). |
| `ALLOW_UEK` | `0` | `1` permite instalar aunque el kernel por defecto sea el UEK. |
| `ALLOW_NOGPG` | `0` | `1` reintenta un paquete sin verificar la firma GPG. Solo para diagnóstico. |
| `ISSABEL_GPG_FPR` | `40D9EB22406CA314E78AC1015C0137F11762DF3D` | Huella esperada de la clave de Issabel. Si no coincide, el script se detiene. |
| `SKIP_PASSWORDS` | `0` | `1` no fija las contraseñas (deberás ejecutar `issabel-admin-passwords --cli init` a mano). |
| `SKIP_UPDATE` | `0` | `1` no ejecuta `dnf update` (ahorra tiempo, pero deja el sistema sin actualizar). |
| `REBOOT` | `0` | `1` reinicia el host al final de la instalación. |
| `COMPAT` | `1` | `0` no genera los RPM de compatibilidad (la instalación **fallará**). |
| `MYSQL_ROOT_PWD` | `Issabel5Db.2026` | Contraseña de root de MariaDB en el primer arranque. |
| `ADMIN_PWD` | `Issabel5Web.2026` | Contraseña del usuario `admin` del panel web y del AMI. |
| `LANG_MODE` | `auto` | Idioma de los mensajes y del log: `es`, `en` o `auto` (elige según el locale del sistema). |

### 4.1 Sobre las contraseñas

Las contraseñas por defecto **son públicas y están en este manual**. Son
suficientes para un laboratorio, pero **no son aceptables en producción**.

- El script solo las aplica la **primera vez** que se ejecuta. En las
  ejecuciones siguientes reutiliza las claves ya guardadas en
  `/etc/issabel.conf`.
- Para no dejarlas nunca en el código, pásalas por entorno (ver 3.2) o
  cámbialas después de la instalación.
- Cambiar la contraseña de root de MariaDB **no** se hace con `ALTER USER`: en
  EL8 el root de MariaDB autentica por `unix_socket`. Usa
  `issabel-admin-passwords --cli change <pwd_mysql> <pwd_admin>` para que
 Issabel se entere.

---

## 5. Resultados esperados

### 5.1 Al terminar correctamente

El script escribe en pantalla y en el log:

```
[2026-10-21 23:58:12] Instalando IssabelPBX (esquema de la BD, ficheros web, modulos y conf de Asterisk)
[2026-10-21 23:58:40] Esquema de IssabelPBX instalado
[2026-10-21 23:58:41] Modulo SELinux 'issabel_selinux' instalado
[2026-10-21 23:58:48] SELinux enforcing con el modulo y las etiquetas de Issabel aplicados
[2026-10-21 23:58:48] Sockets en escucha (revisar 3306 y 5038: solo loopback)
[2026-10-21 23:58:49] Listo. Reinicia, luego: ./issabel5-netinstall-el8.sh --audit
```

Y el **código de salida es 0**.

### 5.2 Estado final del sistema

| Elemento | Estado esperado |
|---|---|
| `asterisk` | activo y habilitado |
| `mariadb` | activo y habilitado |
| `httpd` | habilitado (con SELinux enforcing) |
| `firewalld` | activo, con SSH y HTTPS restringidos a `MGMT_CIDR` |
| SELinux | `Enforcing`, con el módulo `issabel_selinux` cargado |
| Puerto 5038 (AMI) | escuchando solo en `127.0.0.1` |
| Puerto 3306 (MariaDB) | escuchando solo en `127.0.0.1` |
| Puerto 443 (HTTPS) | escuchando en todas las interfaces |
| Panel web | `https://<FQDN>/` responde `200` |
| Base de datos | BD `asterisk` con la tabla `ampusers` y el usuario `admin` |
| `/etc/issabel.conf` | contiene `mysqlrootpwd` y `amiadminpwd` |
| `/var/lib/issabel-netinstall/passwords_done` | existe (marca de instalación completada) |

### 5.3 Códigos de salida

| Código | Significado | Qué hacer |
|---|---|---|
| `0` | Instalación completada | Reinicia y ejecuta `--audit` para revisar. |
| `42` | El host quedó preparado pero hay que reiniciar y reejecutar (caso UEK → RHCK) | Reinicia y vuelve a ejecutar el script. |
| `1` | Fallo real | Revisa `/var/log/issabel-netinstall-errors.txt` y `/var/log/issabel-netinstall.log`. |

---

## 6. Verificación

El repositorio incluye un verificador funcional independiente:

```bash
scp issabel-verify.sh usuario@servidor:/root/
ssh usuario@servidor
sudo bash /root/issabel-verify.sh
```

Comprueba 6 grupos: servicios, MariaDB, Asterisk/AMI, interfaz web (con un
login real contra el panel), exposición de sockets, y hardening (SELinux,
módulos, permisos). Devuelve `0` si todo pasa y `1` si algo falla, e imprime
un resumen:

```
== Resultado ==
  PASS: 31   FAIL: 0
```

### 6.1 Auditoría rápida del propio script

```bash
sudo ./issabel5-netinstall-el8.sh --audit
```

Imprime los sockets en escucha, comprueba que 3306 y 5038 no están
expuestos, valida la clave de MariaDB, la existencia del esquema de la BD, la
interfaz web, el spool de scripts SQL, el estado de Asterisk y el de SELinux.

### 6.2 Comprobaciones manuales

```bash
# Asterisk responde
sudo asterisk -rx 'core show version'

# El AMI acepta el login
sudo nc 127.0.0.1 5038 <<< $'action: login\r\nusername: admin\r\nsecret: Issabel5Web.2026\r\n\r\naction: ping\r\n\r\n'

# El panel web responde
curl -k -o /dev/null -w '%{http_code}\n' https://localhost/

# SELinux y su módulo
getenforce
sudo semodule -l | grep issabel

# Nadie expone MariaDB
sudo ss -tlnp | grep -E '3306|5038'
```

---

## 7. Seguridad por defecto

Qué hace el script para dejar el host en una postura defensiva:

- **MariaDB solo en loopback.** `bind-address=127.0.0.1` en
  `/etc/my.cnf.d/zz-issabel-hardening.cnf`, con permisos `644` (mysqld lo lee
  como el usuario `mysql`: con `600` lo ignora en silencio y sigue escuchando
  en todas las interfaces).
- **AMI solo en loopback.** `bindaddr = 127.0.0.1` en
  `/etc/asterisk/manager.conf`. El panel web habla con Asterisk por la
 loopback.
- **Firmas GPG verificadas.** La clave de Issabel se importa y su huella se
  comprueba contra `ISSABEL_GPG_FPR`. No se usa `--nogpgcheck` salvo que lo
  pidas explícitamente con `ALLOW_NOGPG=1`.
- **Repos saneados.** Se elimina el repositorio de Issabel 4 (EL7, con
  `gpgcheck=0`) que dejaba el script original.
- **SELinux enforcing** con un módulo propio, en lugar de dejarlo en
  `permissive` como hacía el netinstall original.
- **Cortafuegos restringido.** Se eliminan los servicios por defecto de
  `firewalld` y se permiten SSH y HTTPS solo desde `MGMT_CIDR`.
- **Sin addons propietarios** salvo que los pidas con `ADDONS=licensed`.
- **Logs con permisos restrictivos:** `/var/log/issabel-netinstall.log` y
  `/var/log/issabel-netinstall-errors.txt`, en modo `600`.
- **El instalador de Issabel en modo interactivo** (`issabel-firstboot`) se
  deshabilita: en un host sin consola se quedaría colgado en el primer
  arranque.

### 7.1 Lo que el script **no** hace

- No abre los puertos SIP (5060/5061) ni el rango RTP. Deja la decisión a
  quien opera, porque abrirlos sin saber qué troncales hay es la causa
  habitual de exposición accidental. El script imprime la regla exacta que
  hay que añadir:

  ```bash
  firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=203.0.113.10 port port=5060 protocol=udp accept'
  ```

  Remember abrir también el rango RTP definido en `rtp.conf` hacia los
  orígenes que correspondan.
- No cambia las contraseñas que ya están fijadas.
- No deja el AMI expuesto a la red.

---

## 8. Post-instalación

### 8.1 Primer acceso al panel

```
https://<FQDN-del-servidor>/
```

Usuario: `admin` — Contraseña: `ADMIN_PWD` (por defecto `Issabel5Web.2026`).

El certificado TLS es autofirmado: el navegador advertirlo. Es el
comportamiento normal en un laboratorio; en producción, usa un certificado de
una autoridad de certificación.

### 8.2 Cambiar las contraseñas por defecto

```bash
# Contraseña de root de MariaDB y del usuario admin del panel
sudo /usr/bin/issabel-admin-passwords --cli change 'NUEVA_CLAVE_DB' 'NUEVA_CLAVE_ADMIN'
```

Después, el panel web pide recargar la sesión para que el AMI acepte la
nueva clave.

### 8.3 Abrir SIP y RTP

Sólo cuando tengas claro qué troncales y qué IPs van a conectar:

```bash
# SIP
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=IP_TRONCAL port port=5060 protocol=udp accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=IP_TRONCAL port port=5060 protocol=tcp accept'
# RTP (ajusta el rango al de tu rtp.conf)
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=IP_TRONCAL port port="10000-20000" protocol=udp accept'
sudo firewall-cmd --reload
```

No actives el módulo *Firewall* de Issabel mientras `firewalld` esté
gestionando las reglas: se pisarían.

### 8.4 Copias de seguridad

Lo que hay que respaldar:

| Qué | Dónde |
|---|---|
| Base de datos Issabel | `mysqldump -u root -p asterisk` y `asteriskcdrdb` |
| Configuración de Asterisk | `/etc/asterisk/` |
| Configuración del panel | `/etc/amportal.conf`, `/etc/issabel.conf` |
| Módulos y plugins | `/var/www/html/admin/modules/` |
| Grabaciones | `/var/spool/asterisk/monitor/` |

---

## 9. Resolución de problemas

### 9.1 El script termina con 42

**Significado:** el kernel por defecto es el UEK de Oracle y hay que arrancar
con el RHCK.

**Solución:** reinicia y vuelve a ejecutar el script. El script ya dejó el
RHCK como kernel de arranque.

```bash
grubby --default-kernel        # debe mostrar /boot/vmlinuz-4.18.0-...
reboot
```

### 9.2 «tu IP SSH está fuera de MGMT_CIDR»

**Significado:** si aplicas la regla con una red que no incluye tu IP, te
quedas fuera del servidor.

**Solución:** usa la red correcta. Para averiguarla:

```bash
echo $SSH_CLIENT
```

### 9.3 «No se pudo descargar la clave GPG de Issabel»

**Significado:** no hay salida a `repo.issabel.org`, o el mirror está caído.

**Solución:** comprueba la conectividad y los proxies:

```bash
curl -v https://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel
```

### 9.4 «el fingerprint no coincide con ISSABEL_GPG_FPR»

**Significado:** la clave descargada no es la esperada. Puede ser un ataque de
sustitución o un mirror comprometido.

**Solución:** **no continúes**. Verifica la clave por otro canal y, si es
legítima, actualiza `ISSABEL_GPG_FPR` con la huella correcta.

### 9.5 «install_amp --installdb falló»

**Significado:** el script principal de Issabel no pudo crear el esquema de la
base de datos.

**Solución:** mira el detalle en `/tmp/install_amp.log` y en
`journalctl -u asterisk`. La causa más frecuente es que Asterisk no estuviera
arrancado: `install_amp` aborta si no encuentra Asterisk en marcha. Se
resuelve con `sudo systemctl start asterisk` y reejecutando el script.

### 9.6 «no se pudo compilar el módulo SELinux»

**Significado:** falta `checkmodule` o `semodule_package`.

**Solución:**

```bash
sudo dnf install -y checkpolicy policycoreutils policycoreutils-python-utils
```

Si persiste, revisa `/tmp/issabel-selinux.err`.

### 9.7 El panel web no carga

```bash
sudo systemctl status httpd
sudo tail -50 /var/log/httpd/error_log
sudo ausearch -m AVC -ts recent | tail -30   # denegaciones SELinux
```

Comprueba también que el puerto 443 esté abierto desde tu red de gestión.

### 9.8 Asterisk no arranca con SELinux enforcing

```bash
sudo ausearch -m AVC -ts recent | tail -40
sudo journalctl -u asterisk -n 100 --no-pager
```

El módulo `issabel_selinux` debería cubrir los casos habituales (mapeo del
astdb de SQLite, acceso del panel a la configuración de Asterisk, conexión al
AMI). Si aparece una denegación nueva, añade la regla al fichero
`issabel-selinux.te` y vuelve a compilarlo.

### 9.9 El script parece no hacer nada

Comprueba el log, no la salida estándar:

```bash
sudo tail -f /var/log/issabel-netinstall.log
sudo cat /var/log/issabel-netinstall-errors.txt
```

---

## 10. Tiempos y recursos

Medidos en el laboratorio (Oracle Linux 8.10, 2 vCPU, 4 GB de RAM, disco
NVMe, red de 100 Mbps):

| Fase | Tiempo aproximado |
|---|---|
| Habilitar repositorios e importar la clave GPG | 1 – 2 min |
| `dnf update` del sistema | 3 – 5 min |
| Descarga e instalación de paquetes (Asterisk 20, Issabel, PHP 7.4) | 8 – 12 min |
| Creación del esquema, contraseñas y módulo SELinux | 2 – 3 min |
| **Total (con `dnf update`)** | **15 – 22 min** |
| **Total (con `SKIP_UPDATE=1`)** | **10 – 15 min** |
| Reinicio y primera puesta en marcha | 1 – 2 min |

Espacio en disco ocupado por la instalación: unos **4 GB** (paquetes de
Asterisk, PHP 7.4, Issabel, fuentes de sonido y la base de datos).

---

## 11. Idempotencia

El script se puede volver a ejecutar sin miedo:

- Detecta que Issabel ya está inicializado (esquema de la BD, clave en
  `/etc/issabel.conf` y marca `passwords_done`) y no repite la inicialización.
- Los RPM de compatibilidad ya instalados no se regeneran.
- Las contraseñas solo se aplican la primera vez; después se reaplican las
  que ya están en `/etc/issabel.conf`.

Es la base del ciclo de reinstalación del kernel: ejecutar, reiniciar, volver
a ejecutar.

---

## 12. Referencia rápida

```bash
# Instalación típica en laboratorio
MGMT_CIDR=192.168.1.0/24 bash issabel5-netinstall-el8.sh

# Instalación desatendida con claves propias
MGMT_CIDR=192.168.1.0/24 \
MYSQL_ROOT_PWD='...' ADMIN_PWD='...' \
bash issabel5-netinstall-el8.sh

# Solo auditar el estado actual
sudo ./issabel5-netinstall-el8.sh --audit

# Verificación funcional completa
sudo bash issabel-verify.sh

# Ver el log en vivo
sudo tail -f /var/log/issabel-netinstall.log
```

---

## 13. Documentación relacionada

| Documento | Contenido |
|---|---|
| [MANUAL-en.md](MANUAL-en.md) | Este manual, en inglés. |
| [APPLIANCE.md](APPLIANCE.md) | La ISO autoinstalable: qué es, cómo se usa, cómo se construye. |
| [CHARACTERIZATION.md](CHARACTERIZATION.md) | La ficha técnica del sistema resultante, medida en el laboratorio. |
| [DETERMINISM.md](DETERMINISM.md) | La prueba de comportamiento determinista: método, resultados y evidencias. |

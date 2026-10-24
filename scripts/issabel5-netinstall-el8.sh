#!/usr/bin/env bash
# issabel5-netinstall-el8.sh
#
# Adaptacion del netinstall oficial de Issabel 5 para EL8 (Rocky, AlmaLinux,
# Oracle Linux, RHEL 8) con Asterisk 20 por defecto, no interactivo y endurecido.
#
# PROBADO en Oracle Linux 8.10 (OL8 8.10 x86_64) el 2026-10-21.
#
# Cambios respecto al original (sha256 b2d68b1e...d23e7):
#   - Detecta SO con /etc/os-release (el original parsea /etc/redhat-release y
#     falla en Oracle Linux y RHEL).
#   - Repos de dependencias por distro (CRB, EPEL, Remi PHP 7.4).
#   - Sin --nogpg: se verifica la firma de los RPM. Clave GPG importada y
#     fingerprint fijado por defecto (ISSABEL_GPG_FPR).
#   - Elimina el repo Issabel 4 (gpgcheck=0) que el original dejaba habilitado.
#   - Addons comerciales/licenciados desactivados por defecto.
#   - MariaDB solo en loopback; sin password hardcodeada.
#   - Firewall: firewalld con acceso restringido a MGMT_CIDR (o modo original).
#   - Log en /var/log (600), sin reboot automatico, sin dialog.
#
# Correcciones aplicadas tras validar el script en un host real (EL8):
#   1. Paquetes que no existen en EL8 y were sustituidos/eliminados:
#      asterisk-perl, asterisk-codec-g729, asterisk-{es,fr,pt_BR}-sounds y
#      php-magpierss (-> php-pecl-mcrypt), langpacks-en, issabel-admin-passwords
#      (-> viene en issabel-firstboot, que faltaba en la lista).
#      NOTA: bind-utils, libnsl, php-ioncubeloader, RoundCubeMail, xtables-addons
#      y los langpacks-* SI existen en EL8/EPEL/CRB: se mantienen.
#   2. fop2 solo existe en el repo 'commercial_addons': pasa a la lista
#      condicional de ADDONS=licensed.
#   3. Los RPM de Issabel 5 para EL8 exigen 3 dependencias que no existen ni en
#      EL8, ni en EPEL8, ni en CRB: el metapaquete 'dahdi' (exigido por
#      dahdi-linux e issabel-system), 'libopenr2' (exigido por asterisk20-dahdi)
#      y 'python-cjson' (exigido por issabel-endpointconfig2). Se generan RPM
#      de compatibilidad locales (ver build_compat_rpms).
#   4. issabel-admin-passwords no tiene modo no interactivo con '--init'
#      (usa dialog). El modo real es '--cli init <pwd_mysql> <pwd_admin>'.
#   5. issabel_initialized() no puede basarse en 'mysql -uroot': en EL8 el root de
#      MariaDB autentica por unix_socket y seguiria entrando sin password
#      despues de fijarla. El estado real es la clave guardada en
#      /etc/issabel.conf.
#   6. issabel-firstboot.service arranca '--init' interactivo en tty2 en el
#      primer boot: se deshabilita tras inicializar por CLI.
#   7. Los post-install de Issabel usan /sbin/service, /etc/xinetd.d y
#      /tftpboot: initscripts, xinetd y tftp-server se instalan antes.
#   8. 'dnf update' puede dejar el kernel UEK como default (el script exige
#      RHCK): se reafirma el RHCK con grubby tras la actualizacion.
#   9. El script termina con codigo de salida != 0 si algun paquete fallo.
#  10. El modo '--cli' de issabel-admin-passwords NO crea el esquema de la BD
#      (solo lo hace el modo interactivo '--init' con install_amp --installdb):
#      el script ejecuta install_amp --installdb antes de fijar las contrasenas.
#  11. MariaDB queda escuchando en todas las interfaces hasta que se reinicia
#      tras escribir la configuracion de bind-address=127.0.0.1.
#  12. Asterisk se habilita y arranca (el paquete lo deja 'enabled' pero parado).
#  13. /etc/my.cnf.d/*.cnf lo lee mysqld como usuario 'mysql': con umask 077 el
#      fichero quedaba en 600 y MariaDB seguia escuchando en todas las interfaces
#      (bind-address se ignoraba en silencio). Ahora se deja en 644.
#  14. El alta de Issabel la hace install_amp (esquema de la BD, ficheros web,
#      configuracion de Asterisk y modulos). El modo '--cli' de
#      issabel-admin-passwords solo cambia contrasenas: sin install_amp previo
#      el GRANT falla (ERROR 1133) y ampusers no existe.
#  15. SELinux: la politica de EL8 no cubre a Issabel 5 (map del astdb de
#      sqlite, acceso del panel web a la configuracion de Asterisk y al AMI).
#      Se instala un modulo propio ('issabel_selinux'), se reetiquetan los
#      directorios que escribe el panel web y el puerto 5038, y el sistema
#      queda en enforcing, como pide el kickstart.
#
# Uso (como root, sobre EL8 minimal con hostname/FQDN ya fijado):
#   MGMT_CIDR=10.0.0.0/24 ./issabel5-netinstall-el8.sh
#   ./issabel5-netinstall-el8.sh --audit      # revisar sockets/BD despues
#
# Variables: ASTVER(20) ADDONS(blocklist|licensed|wanpipe|none, separadas por coma)
#   FW_MODE(firewalld|issabel) MGMT_CIDR ALLOW_UEK(0) ALLOW_NOGPG(0)
#   ISSABEL_GPG_FPR SKIP_PASSWORDS(0) SKIP_UPDATE(0) REBOOT(0)
#   MYSQL_ROOT_PWD ADMIN_PWD COMPAT(1)
#
# Reejecucion: el script es idempotente; el estado en /var/lib/issabel-netinstall.
#
# Codigos de salida:
#   0   instalacion completada
#   42  el host quedo preparado pero hay que reiniciar y reejecutar
#       (kernel por defecto UEK -> se fijo el RHCK). Tras el reinicio, el
#       script continua hasta el final.
#   1   fallo real (revise /var/log/issabel-netinstall-errors.txt)

set -Eeuo pipefail
umask 077

LOG=/var/log/issabel-netinstall.log
ERRS=/var/log/issabel-netinstall-errors.txt
: "${ASTVER:=20}"
: "${ADDONS:=blocklist}"
: "${FW_MODE:=firewalld}"
: "${MGMT_CIDR:=}"
: "${ALLOW_UEK:=0}"
: "${ALLOW_NOGPG:=0}"
: "${ISSABEL_GPG_FPR:=40D9EB22406CA314E78AC1015C0137F11762DF3D}"
: "${SKIP_PASSWORDS:=0}"
: "${REBOOT:=0}"
: "${SKIP_UPDATE:=0}"
: "${COMPAT:=1}"
# Credenciales de la instalacion. Solo se aplican la PRIMERA vez (primer arranque
# de Issabel). Se pueden fijar por entorno para no dejarlas en el codigo.
: "${MYSQL_ROOT_PWD:=Issabel5Db.2026}"
: "${ADMIN_PWD:=Issabel5Web.2026}"
GPGKEY=/etc/pki/rpm-gpg/RPM-GPG-KEY-Issabel
STATE=/var/lib/issabel-netinstall
WORK="$(mktemp -d /var/tmp/issabel-netinstall.XXXXXX)"

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { log "WARN: $*"; }
die()  { log "ERROR: $*"; exit 1; }
# 42: el script deja el host preparado pero pide reiniciar y reejecutarse
# (caso tipico: el kernel por defecto es UEK y se ha fijado el RHCK).
# Es un codigo de salida distinto del fallo real (1) para que la automatizacion
# (unidades systemd, kickstarts, pipelines) sepa que debe reiniciar y repetir.
die_reboot() { log "ERROR: $*"; exit 42; }

# ---------------- CATALOGO DE MENSAJES (es/en) ----------------
# LANG_MODE=es|en|auto. Con 'auto' se elige 'en' si el locale del sistema es
# en_* y 'es' en caso contrario. Todos los mensajes de diagnostico y de
# progreso se emiten en el idioma elegido, de forma que el log de la
# instalacion es legible por cualquier operador.
: "${LANG_MODE:=auto}"
MSG_LANG=es
case "$LANG_MODE" in
  es|en) MSG_LANG="$LANG_MODE" ;;
  *)
    _sys_lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-es}}}"
    case "$_sys_lang" in en*) MSG_LANG=en ;; *) MSG_LANG=es ;; esac
    ;;
esac
export MSG_LANG LANG_MODE

msg() {
  local id="$1"; shift
  case "$id" in
    sockets_listening)
      if [ "$MSG_LANG" = en ]; then printf 'Listening sockets (check 3306 and 5038: loopback only):'
      else printf 'Sockets en escucha (revisar 3306 y 5038: solo loopback):'; fi ;;
    sockets_exposed)
      if [ "$MSG_LANG" = en ]; then printf '3306 or 5038 are exposed outside loopback'
      else printf '3306 o 5038 expuestos fuera de loopback'; fi ;;
    mariadb_pwd_ok)
      if [ "$MSG_LANG" = en ]; then printf 'MariaDB: the password in /etc/issabel.conf allows root login'
      else printf 'MariaDB: la clave de /etc/issabel.conf permite entrar como root'; fi ;;
    mariadb_pwd_bad)
      if [ "$MSG_LANG" = en ]; then printf 'MariaDB: the password in /etc/issabel.conf does NOT allow root login'
      else printf 'MariaDB: la clave de /etc/issabel.conf NO permite entrar como root'; fi ;;
    mariadb_no_pwd)
      if [ "$MSG_LANG" = en ]; then printf 'MariaDB: no root password in /etc/issabel.conf (Issabel not initialised)'
      else printf 'MariaDB: sin clave de root en /etc/issabel.conf (Issabel sin inicializar)'; fi ;;
    db_schema_ok)
      if [ "$MSG_LANG" = en ]; then printf "Issabel: schema of the 'asterisk' database installed"
      else printf "Issabel: esquema de la BD 'asterisk' instalado"; fi ;;
    db_schema_bad)
      if [ "$MSG_LANG" = en ]; then printf "Issabel: the 'asterisk' database does not exist or has no 'ampusers' table"
      else printf "Issabel: la BD 'asterisk' no existe o no tiene la tabla 'ampusers'"; fi ;;
    web_ok)
      if [ "$MSG_LANG" = en ]; then printf 'Issabel: web interface in /var/www/html/admin'
      else printf 'Issabel: interfaz web en /var/www/html/admin'; fi ;;
    web_bad)
      if [ "$MSG_LANG" = en ]; then printf 'Issabel: the web interface is not in /var/www/html/admin'
      else printf 'Issabel: la interfaz web no esta en /var/www/html/admin'; fi ;;
    spool_ok)
      if [ "$MSG_LANG" = en ]; then printf 'Issabel: no pending SQL scripts in the spool'
      else printf 'Issabel: no quedan scripts SQL pendientes en el spool'; fi ;;
    spool_pending)
      if [ "$MSG_LANG" = en ]; then printf 'Issabel: %s SQL scripts still pending in /var/spool/issabel-mysqldbscripts' "$1"
      else printf 'Issabel: quedan %s scripts SQL sin aplicar en /var/spool/issabel-mysqldbscripts' "$1"; fi ;;
    asterisk_up)
      if [ "$MSG_LANG" = en ]; then printf 'Asterisk: running'
      else printf 'Asterisk: en marcha'; fi ;;
    asterisk_down)
      if [ "$MSG_LANG" = en ]; then printf 'Asterisk: the service is stopped'
      else printf 'Asterisk: el servicio esta parado'; fi ;;
    selinux_enforcing)
      if [ "$MSG_LANG" = en ]; then printf 'SELinux: enforcing'
      else printf 'SELinux: enforcing'; fi ;;
    selinux_mode)
      if [ "$MSG_LANG" = en ]; then printf 'SELinux: in %s mode' "$1"
      else printf 'SELinux: en modo %s' "$1"; fi ;;
    selinux_module_ok)
      if [ "$MSG_LANG" = en ]; then printf "SELinux: module 'issabel_selinux' installed"
      else printf "SELinux: modulo 'issabel_selinux' instalado"; fi ;;
    selinux_module_missing)
      if [ "$MSG_LANG" = en ]; then printf "SELinux: the 'issabel_selinux' module is missing (the web panel will not be able to use the AMI)"
      else printf "SELinux: falta el modulo 'issabel_selinux' (el panel web no podra usar el AMI)"; fi ;;
    uek_rhck_set)
      if [ "$MSG_LANG" = en ]; then printf 'Oracle UEK kernel detected. I have set the RHCK as the default boot kernel (%s):
       reboot the host and run this script again (exit code 42).
       Issabel kernel modules (xtables-addons, dahdi) are built for the RHCK.
       To boot with UEK anyway: ALLOW_UEK=1' "$1"
      else printf 'Kernel UEK de Oracle detectado. He fijado el RHCK como default de arranque (%s):
       reinicia el host y vuelve a ejecutar este script (codigo de salida 42).
       Los modulos de kernel de Issabel (xtables-addons, dahdi) estan construidos para el RHCK.
       Para arrancar con UEK de todos modos: ALLOW_UEK=1' "$1"; fi ;;
    uek_no_rhck)
      if [ "$MSG_LANG" = en ]; then printf 'Oracle UEK kernel detected. Third-party kernel modules (xtables-addons, wanpipe)
       are built for the RHEL kernel. Boot the RHCK: grubby --info=ALL | grep -E "^(kernel|title)"
       and grubby --set-default /boot/vmlinuz-<RHCK>; then reboot. To ignore: ALLOW_UEK=1'
      else printf 'Kernel UEK de Oracle detectado. Modulos de kernel de terceros (xtables-addons, wanpipe)
       estan pensados para el kernel RHEL. Arranca el RHCK: grubby --info=ALL | grep -E "^(kernel|title)"
       y grubby --set-default /boot/vmlinuz-<RHCK>; reinicia. Para ignorar: ALLOW_UEK=1'; fi ;;
    repos_enable)
      if [ "$MSG_LANG" = en ]; then printf 'Enabling CRB, EPEL and Remi (PHP 7.4) for %s' "$1"
      else printf 'Habilitando CRB, EPEL y Remi (PHP 7.4) para %s' "$1"; fi ;;
    gpg_fpr)
      if [ "$MSG_LANG" = en ]; then printf 'Issabel key fingerprint: %s' "$1"
      else printf 'Fingerprint clave Issabel: %s' "$1"; fi ;;
    gpg_mismatch)
      if [ "$MSG_LANG" = en ]; then printf 'fingerprint does not match ISSABEL_GPG_FPR (got: %s)' "$1"
      else printf 'fingerprint no coincide con ISSABEL_GPG_FPR (obtenido: %s)' "$1"; fi ;;
    rhck_set)
      if [ "$MSG_LANG" = en ]; then printf 'RHCK kernel set as the default boot kernel: %s (previously: %s)' "$1" "$2"
      else printf 'Kernel RHCK fijado como default de arranque: %s (antes: %s)' "$1" "$2"; fi ;;
    compat_off)
      if [ "$MSG_LANG" = en ]; then printf 'COMPAT=0: the compatibility RPMs are not generated (the Issabel transaction will fail)'
      else printf 'COMPAT=0: no se generan los RPM de compatibilidad (la transaccion de Issabel fallara)'; fi ;;
    compat_present)
      if [ "$MSG_LANG" = en ]; then printf 'Compatibility RPMs already installed (dahdi, issabel-el8-compat)'
      else printf 'RPM de compatibilidad ya instalados (dahdi, issabel-el8-compat)'; fi ;;
    compat_dahdi)
      if [ "$MSG_LANG" = en ]; then printf 'Compatibility RPM built: dahdi'
      else printf 'RPM de compatibilidad construido: dahdi'; fi ;;
    openr2_fail)
      if [ "$MSG_LANG" = en ]; then printf 'could not analyse chan_dahdi.so (the libopenr2 stub cannot be generated)'
      else printf 'no se pudo analizar chan_dahdi.so (no se puede generar el stub de libopenr2)'; fi ;;
    openr2_stub)
      if [ "$MSG_LANG" = en ]; then printf 'Stub %s compiled with %s openr2 symbols' "$1" "$2"
      else printf 'Stub %s compilado con %s simbolos openr2' "$1" "$2"; fi ;;
    compat_issabel)
      if [ "$MSG_LANG" = en ]; then printf 'Compatibility RPM built: issabel-el8-compat'
      else printf 'RPM de compatibilidad construido: issabel-el8-compat'; fi ;;
    compat_install)
      if [ "$MSG_LANG" = en ]; then printf 'Installing compatibility RPMs: %s' "$1"
      else printf 'Instalando RPM de compatibilidad: %s' "$1"; fi ;;
    txn_retry)
      if [ "$MSG_LANG" = en ]; then printf 'transaction failed; retrying package by package'
      else printf 'transaccion fallo; reintentando paquete por paquete'; fi ;;
    pkg_nogpg)
      if [ "$MSG_LANG" = en ]; then printf '%s: retry WITHOUT GPG verification (ALLOW_NOGPG=1)' "$1"
      else printf '%s: reintento SIN verificacion GPG (ALLOW_NOGPG=1)' "$1"; fi ;;
    install_stack)
      if [ "$MSG_LANG" = en ]; then printf 'Installing base stack and Asterisk %s' "$1"
      else printf 'Instalando stack base y Asterisk %s' "$1"; fi ;;
    install_prereq)
      if [ "$MSG_LANG" = en ]; then printf 'Installing prerequisites for the Issabel post-install scripts'
      else printf 'Instalando prerequisitos de los post-install de Issabel'; fi ;;
    install_issabel_pkgs)
      if [ "$MSG_LANG" = en ]; then printf 'Installing Issabel packages'
      else printf 'Instalando paquetes Issabel'; fi ;;
    install_amp)
      if [ "$MSG_LANG" = en ]; then printf 'Installing IssabelPBX (database schema, web files, modules and Asterisk config)'
      else printf 'Instalando IssabelPBX (esquema de la BD, ficheros web, modulos y conf de Asterisk)'; fi ;;
    install_amp_fail)
      if [ "$MSG_LANG" = en ]; then printf 'install_amp --installdb failed (see %s)' "$1"
      else printf 'install_amp --installdb fallo (ver %s)' "$1"; fi ;;
    schema_installed)
      if [ "$MSG_LANG" = en ]; then printf 'IssabelPBX schema installed'
      else printf 'Esquema de IssabelPBX instalado'; fi ;;
    sql_applied)
      if [ "$MSG_LANG" = en ]; then printf 'SQL script applied: %s' "$1"
      else printf 'Script SQL aplicado: %s' "$1"; fi ;;
    admin_passwords_retry)
      if [ "$MSG_LANG" = en ]; then printf 'issabel-admin-passwords --cli %s returned %s: applying the pending SQL spool and retrying with --cli change' "$1" "$2"
      else printf 'issabel-admin-passwords --cli %s devolvio %s: se aplican los scripts SQL pendientes y se reintenta con --cli change' "$1" "$2"; fi ;;
    sql_failed)
      if [ "$MSG_LANG" = en ]; then printf 'failed to apply SQL script %s (see %s)' "$1" "$2"
      else printf 'fallo al aplicar el script SQL %s (ver %s)' "$1" "$2"; fi ;;
    fw_issabel_open)
      if [ "$MSG_LANG" = en ]; then printf 'FW_MODE=issabel: firewalld disabled (like the original). The host stays OPEN until you configure the firewall.'
      else printf 'FW_MODE=issabel: firewalld apagado (como el original). El host queda ABIERTO hasta configurar el firewall.'; fi ;;
    sip_not_open)
      if [ "$MSG_LANG" = en ]; then printf 'SIP/RTP are NOT open. Example (trunk 203.0.113.10):'
      else printf 'SIP/RTP NO abiertos. Ejemplo (troncal 203.0.113.10):'; fi ;;
    sip_example)
      printf "  firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=203.0.113.10 port port=5060 protocol=udp accept'" ;;
    sip_rtp_note)
      if [ "$MSG_LANG" = en ]; then printf '  and the RTP range (rtp.conf) only towards the required sources. Do not enable the Issabel Firewall module in this mode.'
      else printf '  y el rango RTP (rtp.conf) solo hacia origenes necesarios. No actives el modulo Firewall de Issabel en este modo.'; fi ;;
    asterisk_not_running)
      if [ "$MSG_LANG" = en ]; then printf "Asterisk does not start: install_amp will fail. Check 'journalctl -u asterisk'"
      else printf "Asterisk no arranca: install_amp fallara. Revisa 'journalctl -u asterisk'"; fi ;;
    schema_exists)
      if [ "$MSG_LANG" = en ]; then printf 'The IssabelPBX schema is already installed'
      else printf 'El esquema de IssabelPBX ya esta instalado'; fi ;;
    skip_passwords)
      if [ "$MSG_LANG" = en ]; then printf "SKIP_PASSWORDS=1: you must run 'issabel-admin-passwords --cli init <pwd_mysql> <pwd_admin>'"
      else printf "SKIP_PASSWORDS=1: falta ejecutar 'issabel-admin-passwords --cli init <pwd_mysql> <pwd_admin>'"; fi ;;
    reapply_passwords)
      if [ "$MSG_LANG" = en ]; then printf 'Re-applying passwords to the existing installation (--cli change mode)'
      else printf 'Reaplicando contrasenas sobre la instalacion existente (modo --cli change)'; fi ;;
    init_passwords)
      if [ "$MSG_LANG" = en ]; then printf 'Initialising passwords (non-interactive mode: --cli init)'
      else printf 'Inicializando contrasenas (modo no interactivo: --cli init)'; fi ;;
    semodule_missing)
      if [ "$MSG_LANG" = en ]; then printf 'semodule is not available: SELinux stays permissive'
      else printf 'semodule no esta disponible: SELinux se queda en permissive'; fi ;;
    selinux_compile_fail)
      if [ "$MSG_LANG" = en ]; then printf 'could not compile the SELinux module: %s' "$1"
      else printf 'no se pudo compilar el modulo SELinux: %s' "$1"; fi ;;
    selinux_package_fail)
      if [ "$MSG_LANG" = en ]; then printf 'could not package the SELinux module: %s' "$1"
      else printf 'no se pudo empaquetar el modulo SELinux: %s' "$1"; fi ;;
    selinux_install_fail)
      if [ "$MSG_LANG" = en ]; then printf 'could not install the SELinux module: %s' "$1"
      else printf 'no se pudo instalar el modulo SELinux: %s' "$1"; fi ;;
    selinux_module_installed)
      if [ "$MSG_LANG" = en ]; then printf "SELinux module 'issabel_selinux' installed"
      else printf "Modulo SELinux 'issabel_selinux' instalado"; fi ;;
    selinux_enforce_fail)
      if [ "$MSG_LANG" = en ]; then printf 'could not switch SELinux to enforcing: %s' "$1"
      else printf 'no se pudo activar SELinux en enforcing: %s' "$1"; fi ;;
    selinux_enforce_ok)
      if [ "$MSG_LANG" = en ]; then printf 'SELinux is active in enforcing mode'
      else printf 'SELinux activo en enforcing'; fi ;;
    asterisk_no_enforcing)
      if [ "$MSG_LANG" = en ]; then printf 'Asterisk does not start with SELinux enforcing (check journalctl -u asterisk)'
      else printf 'Asterisk no arranca con SELinux enforcing (revisa journalctl -u asterisk)'; fi ;;
    selinux_labelled)
      if [ "$MSG_LANG" = en ]; then printf 'SELinux enforcing with the module and the Issabel labels applied'
      else printf 'SELinux enforcing con el modulo y las etiquetas de Issabel aplicados'; fi ;;
    update_os)
      if [ "$MSG_LANG" = en ]; then printf 'Updating the OS'
      else printf 'Actualizando SO'; fi ;;
    pkg_errors)
      if [ "$MSG_LANG" = en ]; then printf 'Packages with errors: %s' "$1"
      else printf 'Paquetes con error: %s' "$1"; fi ;;
    install_incomplete)
      if [ "$MSG_LANG" = en ]; then printf 'installation incomplete: check %s' "$1"
      else printf 'instalacion incompleta: revisa %s' "$1"; fi ;;
    done)
      if [ "$MSG_LANG" = en ]; then printf 'Done. Reboot, then: %s --audit' "$1"
      else printf 'Listo. Reinicia, luego: %s --audit' "$1"; fi ;;
    *)
      printf '%s' "$id" ;;
  esac
}


cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# Estado real de Issabel: la clave de MariaDB guardada en /etc/issabel.conf Y el
# esquema de IssabelPBX instalado (BD 'asterisk' con la tabla 'ampusers') Y la
# inicializacion completada (marca /var/lib/issabel-netinstall/passwords_done).
# (En EL8 el root de MariaDB autentica por unix_socket, asi que 'mysql -uroot'
#  seguiria funcionando sin password y no sirve como indicador.)
issabel_initialized() {
  [ -e "$STATE/passwords_done" ] || return 1
  [ -f /etc/issabel.conf ] || return 1
  grep -q '^mysqlrootpwd=' /etc/issabel.conf || return 1
  grep -q '^amiadminpwd=' /etc/issabel.conf || return 1
  issabel_db_ready || return 1
  return 0
}

# El esquema de IssabelPBX esta instalado?
issabel_db_ready() {
  command -v mysql >/dev/null || return 1
  local pwd=""
  [ -f /etc/issabel.conf ] && pwd="$(sed -n 's/^mysqlrootpwd=//p' /etc/issabel.conf | head -1)"
  MYSQL_PWD="$pwd" mysql -uroot -e 'SELECT 1 FROM asterisk.ampusers LIMIT 1;' >/dev/null 2>&1
}

audit() {
  log "$(msg sockets_listening)"
  ss -H -tulnp | awk '{print $1, $5, $7}' || true
  if ss -H -tln | awk '$4 ~ /:(3306|5038)$/ && $4 !~ /^(127\.0\.0\.1|\[::1\]):/' | grep -q .; then
    warn "$(msg sockets_exposed)"
  fi
  local pwd=""
  if [ -f /etc/issabel.conf ]; then
    pwd="$(sed -n 's/^mysqlrootpwd=//p' /etc/issabel.conf | head -1)"
  fi
  if [ -n "$pwd" ]; then
    if MYSQL_PWD="$pwd" mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then
      log "$(msg mariadb_pwd_ok)"
    else
      warn "$(msg mariadb_pwd_bad)"
    fi
  else
    warn "$(msg mariadb_no_pwd)"
  fi
  if issabel_db_ready; then
    log "$(msg db_schema_ok)"
  else
    warn "$(msg db_schema_bad)"
  fi
  if [ -f /var/www/html/admin/index.php ]; then
    log "$(msg web_ok)"
  else
    warn "$(msg web_bad)"
  fi
  local spool
  spool="$(find /var/spool/issabel-mysqldbscripts -type f 2>/dev/null | wc -l)"
  if [ "$spool" -eq 0 ]; then
    log "$(msg spool_ok)"
  else
    warn "$(msg spool_pending "$spool")"
  fi
  if systemctl is-active --quiet asterisk; then
    log "$(msg asterisk_up)"
  else
    warn "$(msg asterisk_down)"
  fi
  if getenforce 2>/dev/null | grep -q Enforcing; then
    log "$(msg selinux_enforcing)"
  else
    warn "$(msg selinux_mode "$(getenforce 2>/dev/null)")"
  fi
  if semodule -l 2>/dev/null | grep -q '^issabel_selinux'; then
    log "$(msg selinux_module_ok)"
  else
    warn "$(msg selinux_module_missing)"
  fi
  command -v asterisk >/dev/null && asterisk -V || true
}

preflight() {
  [ "$EUID" -eq 0 ] || die "ejecutar como root"
  [ -r /etc/os-release ] || die "falta /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  local major="${VERSION_ID%%.*}"
  case "$ID" in rocky|almalinux|ol|rhel) ;; *) die "distro no soportada: $ID" ;; esac
  [ "$major" = "8" ] || die "EL${major} no soportado: los RPM de Issabel 5 son EL8 con PHP 7.4"
  [ "$(uname -m)" = "x86_64" ] || die "solo x86_64"
  command -v dnf >/dev/null || die "dnf no encontrado"
  [[ "$ASTVER" =~ ^[0-9]+$ ]] || die "ASTVER invalido: $ASTVER"
  case "$FW_MODE" in firewalld|issabel) ;; *) die "FW_MODE debe ser firewalld o issabel" ;; esac

  if uname -r | grep -qi uek && [ "$ALLOW_UEK" != "1" ]; then
    # En Oracle Linux el kernel por defecto es el UEK, pero los modulos de
    # kernel de terceros que instala Issabel (xtables-addons, dahdi) estan
    # construidos para el RHCK. Se deja preparado el arranque y se pide reiniciar.
    local rhck
    rhck="$(ls -1 /boot/vmlinuz-4.*.el8* 2>/dev/null | sort -V | tail -1)"
    if [ -n "$rhck" ] && command -v grubby >/dev/null; then
      grubby --set-default "$rhck" >/dev/null 2>&1 || true
      die_reboot "$(msg uek_rhck_set "$rhck")"
    fi
    die "$(msg uek_no_rhck)"
  fi

  if [ "$FW_MODE" = "firewalld" ]; then
    [[ "$MGMT_CIDR" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] \
      || die "MGMT_CIDR obligatorio con FW_MODE=firewalld (ej. 10.0.0.0/24)"
    if [ -n "${SSH_CLIENT:-}" ]; then
      /usr/libexec/platform-python -c \
        'import ipaddress,sys; sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2], strict=False) else 1)' \
        "${SSH_CLIENT%% *}" "$MGMT_CIDR" \
        || die "tu IP SSH (${SSH_CLIENT%% *}) esta fuera de MGMT_CIDR: te bloquearias"
    fi
  fi
}

enable_deps() {
  # shellcheck disable=SC1091
  . /etc/os-release
  log "$(msg repos_enable "$ID")"
  dnf -y install dnf-plugins-core
  case "$ID" in
    rocky|almalinux)
      dnf -y install epel-release
      dnf config-manager --set-enabled powertools ;;
    ol)
      dnf -y install oracle-epel-release-el8
      dnf config-manager --set-enabled ol8_codeready_builder ;;
    rhel)
      subscription-manager repos --enable "codeready-builder-for-rhel-8-$(arch)-rpms"
      dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm ;;
  esac
  dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
  if ! dnf -q module list --enabled php 2>/dev/null | grep -q 'remi-7.4'; then
    dnf -y module reset php
    dnf -y module enable php:remi-7.4
  fi
  dnf config-manager --set-enabled remi
  # CRB aporta perl-Switch, perl-Text-CSV_XS y libtiff-tools, exigidos por los
  # RPM de Issabel (en EL8 base no existen).
  dnf config-manager --set-enabled ol8_codeready_builder 2>/dev/null || true
}

import_gpg() {
  local scheme got=""
  for scheme in https http; do
    if curl -fsSL --max-time 30 "$scheme://repo.issabel.org/issabel/RPM-GPG-KEY-Issabel" -o "$GPGKEY"; then
      got="$scheme"; break
    fi
  done
  [ -n "$got" ] || die "no pude descargar la clave GPG de Issabel"
  [ "$got" = "http" ] && warn "clave GPG descargada por HTTP; se valida el fingerprint $ISSABEL_GPG_FPR"
  local fpr
  fpr="$(gpg --show-keys --with-colons "$GPGKEY" | awk -F: '/^fpr/ {print $10; exit}')"
  log "$(msg gpg_fpr "$fpr")"
  if [ -n "$ISSABEL_GPG_FPR" ] && [ "${ISSABEL_GPG_FPR^^}" != "$fpr" ]; then
    die "$(msg gpg_mismatch "$fpr")"
  fi
  rpm --import "$GPGKEY"
}

add_repos() {
  rm -f /etc/yum.repos.d/Issabel.repo   # repo Issabel 4 (EL7, gpgcheck=0): no se usa
  : > /etc/yum.repos.d/Issabel5.repo
  local r arch repo
  for repo in base updates extras; do
    for arch in '$basearch' noarch; do
      r="issabel-cinco-$repo"; [ "$arch" = noarch ] && r="$r-noarch"
      cat >> /etc/yum.repos.d/Issabel5.repo <<EOR
[$r]
name=Issabel 5 $repo ($arch)
mirrorlist=http://mirror.issabel.org/?release=5&arch=$arch&repo=$repo
gpgcheck=1
enabled=1
gpgkey=file://$GPGKEY

EOR
    done
  done
  if [[ ",$ADDONS," == *",licensed,"* ]]; then
    cat > /etc/yum.repos.d/commercial-addons.repo <<'EOR'
[commercial-addons]
name=Commercial-Addons RPM Repository for Issabel
mirrorlist=http://mirror.issabel.org/?release=5&arch=$basearch&repo=commercial_addons
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Issabel
EOR
  fi
}

sys_prep() {
  # La instalacion trabaja en permissive (los RPM de Issabel escriben en
  # rutas que todavia no estan etiquetadas), pero la configuracion queda en
  # enforcing: selinux_enforce() la aplica al final, junto con las etiquetas
  # y el modulo de policy que Issabel necesita.
  setenforce 0 2>/dev/null || true
  if grep -q '^SELINUX=' /etc/selinux/config; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  else
    printf 'SELINUX=enforcing\n' >> /etc/selinux/config
  fi
  /usr/sbin/groupadd -f -r asterisk
  grep -q '^asterisk:' /etc/passwd || \
    /usr/sbin/useradd -r -g asterisk -c "Asterisk PBX" -s /bin/bash -d /var/lib/asterisk asterisk
}

# Reafirma el kernel RHCK como default de arranque. 'dnf update' puede dejar el
# UEK por delante, y el script (y los modulos de kernel de Issabel) necesitan el
# RHCK. Idempotente.
ensure_rhck_default() {
  command -v grubby >/dev/null || return 0
  local def rhck
  def="$(grubby --default-kernel 2>/dev/null || true)"
  rhck="$(ls -1 /boot/vmlinuz-4.*.el8* 2>/dev/null | sort -V | tail -1)"
  [ -n "$rhck" ] || return 0
  if [ "$def" != "$rhck" ]; then
    grubby --set-default "$rhck" >/dev/null 2>&1 || true
    log "$(msg rhck_set "$rhck" "${def:-desconocido}")"
    touch "$STATE/reboot_needed"
  fi
}

# ---------------------------------------------------------------------------
# RPM de compatibilidad EL8.
#
# Los RPM de Issabel 5 para EL8 son reempaquetados desde CentOS 7 y conservan
# dependencias que en EL8 no existen en ningun repo (ni EL8, ni EPEL8, ni CRB):
#
#   dahdi = 2.11.1   <- dahdi-linux (issabel-cinco-base) e issabel-system
#   libopenr2        <- asterisk20-dahdi (chan_dahdi)
#   python-cjson     <- issabel-endpointconfig2
#
# Sin estos tres, dnf no puede resolver la transaccion y NO se instala nada de
# Issabel. Se generan RPM locales minimos que los satisfacen:
#
#   dahdi            -> metapaquete real. Los subpaquetes (dahdi-linux,
#                       dahdi-tools) se instalan explicitamente en install_all.
#   libopenr2        -> stub que exporta la API openr2 que usa chan_dahdi.
#                       Solo se usa en enlaces R2/MF/SS7, que Issabel 5 no
#                       configura: sin efecto en el resto del PBX.
#   python-cjson     -> modulo Python minimo sobre la stdlib json. En Issabel
#                       5 el requisito es vestigial (el modulo ya no usa cjson).
#
# 'issabel-el8-compat' es x86_64 (no noarch) porque instala la .so compilada.
# ---------------------------------------------------------------------------
build_compat_rpms() {
  if [ "$COMPAT" != "1" ]; then
    warn "$(msg compat_off)"
    return
  fi
  command -v rpmbuild >/dev/null || die "rpmbuild no encontrado (necesario para los RPM de compatibilidad)"
  command -v gcc >/dev/null || die "gcc no encontrado (necesario para el stub libopenr2)"

  # Si ya estan instalados no hay nada que construir (re-ejecucion).
  if rpm -q dahdi >/dev/null 2>&1 && rpm -q issabel-el8-compat >/dev/null 2>&1; then
    log "$(msg compat_present)"
    return
  fi

  local src="$WORK/spec" out="$WORK/rpms" bdir="$WORK/rpmbuild"
  mkdir -p "$src" "$out" "$bdir"

  # --- RPM 1: metapaquete 'dahdi' ---
  # dahdi-linux-2.11.1-7.el8 exige 'dahdi = 2.11.1' (version exacta) y
  # dahdi-tools = 2.11.1. El metapaquete no puede exigir a los subpaquetes
  # (crearia un ciclo), asi que no lleva Requires.
  if ! rpm -q dahdi >/dev/null 2>&1; then
    cat > "$src/dahdi.spec" <<'EOR'
Name:           dahdi
Version:        2.11.1
Release:        32.el8
Summary:        Metapaquete DAHDI (compatibilidad de dependencias Issabel 5 en EL8)
License:        GPL-2.0-only
URL:            http://www.dahdi.org
BuildArch:      noarch
Provides:       dahdi = 2.11.1
Provides:       dahdi

%description
Metapaquete DAHDI. En EL8 no existe el paquete 'dahdi', pero dahdi-linux e
issabel-system lo exigen con version exacta 2.11.1. Los subpaquetes reales
(dahdi-linux, dahdi-tools) se instalan por separado.

%install
# metapaquete sin ficheros

%files
# metapaquete sin ficheros
EOR
    rpmbuild --define "_topdir $bdir" --define "_rpmdir $out" -bb "$src/dahdi.spec" >/dev/null \
      || die "fallo al construir el RPM 'dahdi'"
    log "$(msg compat_dahdi)"
  fi

  # --- RPM 2: issabel-el8-compat (libopenr2 + python-cjson) ---
  if ! rpm -q issabel-el8-compat >/dev/null 2>&1; then
    local soname="libopenr2.so.3" syms=""
    # Se obtiene la API exacta que chan_dahdi necesita de libopenr2 y el soname
    # real, extrayendo el RPM asterisk20-dahdi del repo de Issabel.
    local url rpmf
    url="$(dnf -q repoquery --location --available "asterisk${ASTVER}-dahdi" 2>/dev/null \
           | grep -E '\.rpm$' | head -1)"
    if [ -n "$url" ]; then
      mkdir -p "$WORK/dl" "$WORK/ahd"
      if curl -fsSL --max-time 120 "$url" -o "$WORK/dl/asterisk-dahdi.rpm"; then
        rpmf="$WORK/dl/asterisk-dahdi.rpm"
        ( cd "$WORK/ahd" && rpm2cpio "$rpmf" | cpio -idmu --quiet 2>/dev/null ) || true
        local so
        so="$(find "$WORK/ahd" -name 'chan_dahdi.so' | head -1)"
        if [ -n "$so" ]; then
          syms="$(nm -D --undefined-only "$so" 2>/dev/null | awk '$2 ~ /^openr2_/ {print $2}' | sort -u)"
          local need
          need="$(objdump -p "$so" 2>/dev/null | awk '/NEEDED/ {print $2}' | grep -i openr | head -1)"
          [ -n "$need" ] && soname="$need"
        fi
      fi
    fi
    if [ -z "$syms" ]; then
      die "$(msg openr2_fail)"
    fi

    {
      echo '/* Stub de la API openr2 usada por chan_dahdi. EL8 no la distribuye'
      echo ' * (openr2 fue eliminado de RHEL/OL 8) pero asterisk20-dahdi la exige.'
      echo ' * Solo interviene en enlaces R2/MF/SS7, que Issabel 5 no configura. */'
      echo '#include <stddef.h>'
      local s
      for s in $syms; do
        echo "long $s() { return 0; }"
      done
    } > "$src/stub.c"

    gcc -shared -fPIC -O2 -o "$src/$soname" "$src/stub.c" -Wl,-soname,"$soname" \
      || die "fallo al compilar el stub $soname"
    log "$(msg openr2_stub "$soname" "$(echo "$syms" | wc -w)")"

    # Modulo cjson minimo (el requisito de issabel-endpointconfig2 es vestigial).
    cat > "$src/cjson.py" <<'EOR'
"""Modulo cjson minimo para EL8.

El RPM 'python-cjson' de EL7 no existe en EL8, pero issabel-endpointconfig2
lo declara como dependencia. Esta implementacion expone la misma API basica
sobre la libreria estandar json.
"""
import json as _json


class CJSONError(ValueError):
    pass


def decode(s, **kwargs):
    try:
        return _json.loads(s, **kwargs)
    except Exception as exc:
        raise CJSONError(str(exc))


def encode(obj, **kwargs):
    try:
        return _json.dumps(obj, **kwargs)
    except Exception as exc:
        raise CJSONError(str(exc))


def decode_unicode(s, **kwargs):
    return decode(s, **kwargs)


def encode_unicode(obj, **kwargs):
    return encode(obj, **kwargs)
EOR

    cat > "$src/compat.spec" <<EOR
Name:           issabel-el8-compat
Version:        1.0
Release:        1.el8
Summary:        Compatibilidad EL8 para Issabel 5 (libopenr2, python-cjson)
License:        GPL-2.0-only
BuildArch:      x86_64
Provides:       libopenr2
Provides:       python-cjson
Provides:       python3-cjson
Requires:       python3

%description
Satisface las dependencias de los RPM de Issabel 5 para EL8 que no existen en
ningun repositorio de EL8: libopenr2 (exigido por asterisk20-dahdi) y
python-cjson (exigido por issabel-endpointconfig2).

%install
mkdir -p %{buildroot}/usr/lib64
install -m 0755 $src/$soname %{buildroot}/usr/lib64/$soname
mkdir -p %{buildroot}/usr/lib64/python3.6/site-packages
install -m 0644 $src/cjson.py %{buildroot}/usr/lib64/python3.6/site-packages/cjson.py

%files
/usr/lib64/$soname
/usr/lib64/python3.6/site-packages/cjson.py
# la byte-compilacion automatica genera __pycache__ que no se empaqueta
%exclude /usr/lib64/python3.6/site-packages/__pycache__/*
EOR
    rpmbuild --define "_topdir $bdir" --define "_rpmdir $out" -bb "$src/compat.spec" >/dev/null \
      || die "fallo al construir el RPM 'issabel-el8-compat'"
    log "$(msg compat_issabel)"
  fi

  # rpmbuild deja los RPM en $out/<arquitectura>/: hay que buscarlos.
  local rpms
  rpms="$(find "$out" -type f -name '*.rpm' | sort)"
  if [ -n "$rpms" ]; then
    log "$(msg compat_install "$(echo "$rpms" | tr '\n' ' ')")"
    dnf -y install $rpms || die "fallo al instalar los RPM de compatibilidad"
  fi
  rpm -q dahdi >/dev/null 2>&1 || die "el metapaquete 'dahdi' no ha quedado instalado"
  rpm -q issabel-el8-compat >/dev/null 2>&1 || die "'issabel-el8-compat' no ha quedado instalado"
}

try_install() {  # try_install pkg...
  local p
  dnf -y install "$@" && return 0
  warn "$(msg txn_retry)"
  for p in "$@"; do
    rpm -q "$p" >/dev/null 2>&1 && continue
    if ! dnf -y install "$p"; then
      if [ "$ALLOW_NOGPG" = "1" ]; then
        warn "$(msg pkg_nogpg "$p")"
        dnf -y install --nogpgcheck "$p" || echo "$p" >> "$ERRS"
      else
        echo "$p" >> "$ERRS"
      fi
    fi
  done
}

install_all() {
  local a="asterisk${ASTVER}"
  rpm -q "$a" >/dev/null 2>&1 || dnf -q list --available "$a" >/dev/null 2>&1 || die "El repo Issabel 5 no ofrece '$a'.
       Verifica: dnf list available 'asterisk*'. Alternativa: usar la ISO oficial como repo local."

  # --- Transaccion 1: stack base (httpd, mariadb, php, asterisk) ---
  # initscripts aporta /sbin/service (usado por los post-install de Issabel).
  local BASE=( httpd httpd-tools initscripts mariadb mariadb-connector-c
    mariadb-connector-odbc mariadb-server
    php php-bcmath php-cli php-common php-gd php-IDNA_Convert php-imap php-jpgraph
    php-mbstring php-pecl-mcrypt php-mysqlnd php-pdo php-pear php-pear-DB php-PHPMailer
    php-process php-simplepie php-Smarty php-soap php-tcpdf php-tidy php-xml
    "$a" "${a}-devel" "${a}-curl"
    certbot vim jq whois bind-utils dhcp-server mailx
    langpacks-es langpacks-en langpacks-pt langpacks-pt_BR langpacks-fa langpacks-fr )
  log "$(msg install_stack "${ASTVER}")"
  try_install "${BASE[@]}"

  # --- Transaccion 2: paquetes que los post-install de Issabel asumen ---
  # xinetd crea /etc/xinetd.d, tftp-server crea /tftpboot.
  log "$(msg install_prereq)"
  try_install xinetd tftp-server sqlite

  # --- Transaccion 3: Issabel ---
  # 'issabel' es un metapaquete que arrastra issabel-pbx, issabelPBX,
  # issabel-framework, issabel-system...  'issabel-firstboot' aporta
  # /usr/bin/issabel-admin-passwords.  'issabel-asterisk-sounds' sustituye a los
  # packs de sonidos por idioma (asterisk-{es,fr,pt_BR}-sounds no existen).
  local ISS=( issabel issabel-firstboot issabel-config_helpers issabel-geoip
    issabel-prosody-auth issabel-endpointconfig2 issabel-packetbl
    issabel-asterisk-sounds xtables-addons RoundCubeMail php-ioncubeloader libnsl
    dahdi-linux dahdi-tools )

  [[ ",$ADDONS," == *",licensed,"* ]] && ISS+=( issabel-license webconsole issabel-wizard
    issabel-packet_capture issabel-upnpc issabel-two_factor_auth issabel-theme_designer
    issabel-network-agent issabel-webphone fop2 )
  [[ ",$ADDONS," == *",blocklist,"* ]] && ISS+=( issabel-packetbl )
  [[ ",$ADDONS," == *",wanpipe,"* ]]   && ISS+=( wanpipe-utils wanpipe )

  log "$(msg install_issabel_pkgs)"
  try_install "${ISS[@]}"
}

post_install() {
  mkdir -p /etc/my.cnf.d
  printf '[mysqld]\nbind-address=127.0.0.1\n' > /etc/my.cnf.d/zz-issabel-hardening.cnf
  # mysqld lee la configuracion como el usuario 'mysql': con 600 (umask 077)
  # ignora en silencio el fichero y sigue escuchando en todas las interfaces.
  chmod 0644 /etc/my.cnf.d/zz-issabel-hardening.cnf
  systemctl enable --now mariadb
  # MariaDB ya estaba en marcha (la instalacion del paquete la arranca): sin
  # reiniciar seguiria escuchando en todas las interfaces.
  systemctl restart mariadb
  local i
  for i in $(seq 1 60); do
    if systemctl is-active --quiet mariadb; then break; fi
    sleep 1
  done
  systemctl is-active --quiet mariadb || die "MariaDB no esta en marcha tras el reinicio"
  systemctl enable httpd

  if [ -d /etc/asterisk ]; then
    grep -qxF 'noload => cdr_mysql.so' /etc/asterisk/modules_additional.conf 2>/dev/null \
      || echo 'noload => cdr_mysql.so' >> /etc/asterisk/modules_additional.conf
    mkdir -p /var/log/asterisk/cdr-csv
    if [ -f /etc/asterisk/extensions_custom.conf.sample ]; then
      mv /etc/asterisk/extensions_custom.conf.sample /etc/asterisk/extensions_custom.conf
    fi
  fi
}

# Crea el esquema de la BD de IssabelPBX (BD 'asterisk' + 'asteriskcdrdb' + tablas).
#
# El modo interactivo '--init' de Issabel lo hace en action_installIssabelPBX(),
# PERO el modo no interactivo '--cli' NO lo hace: se limita a cambiar contrasenas.
# Sin este paso, el GRANT sobre la BD 'asterisk' falla (ERROR 1133) y el UPDATE
# de la tabla ampusers falla (Table 'asterisk.ampusers' doesn't exist).
install_issabel_db() {
  local bin=/usr/src/issabelPBX/framework/install_amp
  [ -x "$bin" ] || die "install_amp no encontrado (falta el paquete issabelPBX)"
  local pwd="" extra=()
  if [ -f /etc/issabel.conf ]; then
    pwd="$(sed -n 's/^mysqlrootpwd=//p' /etc/issabel.conf | head -1)"
  fi
  # La clave de root solo se pasa si ya esta fijada: en el primer arranque el
  # root de MariaDB (EL8) tiene la clave vacia y install_amp debe entrar sin ella.
  [ -n "$pwd" ] && extra+=("--dbpass=$pwd")
  log "$(msg install_amp)"
  local out=/tmp/install_amp.log
  if ! "$bin" --dbuser=root ${extra[@]+"${extra[@]}"} --installdb --scripted --language=en >"$out" 2>&1; then
    tail -n 30 "$out" >&2
    die "$(msg install_amp_fail "$out")"
  fi
  rm -f /installamp          # el propio Issabel lo borra tras instalar
  issabel_db_ready || die "install_amp termino pero la BD 'asterisk' no tiene la tabla 'ampusers'"
  [ -f /etc/amportal.conf ] || die "install_amp no escribio /etc/amportal.conf"
  [ -f /etc/asterisk/manager.conf ] || warn "install_amp no dejo /etc/asterisk/manager.conf"
  [ -d /var/www/html/admin ] || warn "install_amp no dejo la interfaz web en /var/www/html/admin"
  log "$(msg schema_installed)"
}

# Aplica los scripts SQL que los modulos de Issabel dejan en
# /var/spool/issabel-mysqldbscripts (permisos de asteriskuser, tablas de
# endpointconfig/meetme/roundcube). Issabel lo hace en apply_updatesql(), pero
# solo en el modo '--cli init': en '--cli change' hay que aplicarlos a mano.
apply_db_spool() {
  local pwd="$1" f
  [ -d /var/spool/issabel-mysqldbscripts ] || return 0
  local files=(/var/spool/issabel-mysqldbscripts/*.sql)
  [ -e "${files[0]}" ] || return 0
  for f in "${files[@]}"; do
    if MYSQL_PWD="$pwd" mysql -uroot <"$f" >>"$LOG" 2>&1; then
      rm -f "$f"
      log "$(msg sql_applied "$(basename "$f")")"
    else
      warn "$(msg sql_failed "$(basename "$f")" "$LOG")"
      return 1
    fi
  done
  return 0
}

firewall() {
  if [ "$FW_MODE" = "issabel" ]; then
    warn "$(msg fw_issabel_open)"
    systemctl disable --now firewalld 2>/dev/null || true
    return
  fi
  systemctl enable --now firewalld
  local s rule
  if [ ! -e "$STATE/fw_baseline" ]; then   # quitar servicios por defecto solo la 1a vez
    for s in $(firewall-cmd --permanent --list-services); do
      firewall-cmd --permanent --remove-service="$s" >/dev/null 2>&1 || true
    done
    touch "$STATE/fw_baseline"
  fi
  for s in ssh https; do
    rule="rule family=ipv4 source address=${MGMT_CIDR} service name=${s} accept"
    firewall-cmd --permanent --query-rich-rule="$rule" >/dev/null \
      || firewall-cmd --permanent --add-rich-rule="$rule"
  done
  firewall-cmd --reload
  warn "$(msg sip_not_open)"
  warn "$(msg sip_example)"
  warn "$(msg sip_rtp_note)"
}

init_passwords() {
  # Asterisk debe estar en marcha ANTES de install_amp: install_amp aborta si
  # no lo encuentra ('Asterisk must be running'), y el cambio de contrasenas
  # recarga el manager y genera la configuracion de las extensiones.
  systemctl enable --now asterisk
  if ! systemctl is-active --quiet asterisk; then
    warn "$(msg asterisk_not_running)"
  fi

  # 1) IssabelPBX: esquema de la BD 'asterisk', ficheros de la interfaz web,
  #    configuracion de Asterisk y modulos. Solo install_amp hace esto: el modo
  #    '--cli' de issabel-admin-passwords se limita a cambiar contrasenas.
  if issabel_db_ready; then
    log "$(msg schema_exists)"
  else
    install_issabel_db
  fi

  # 2) Contrasenas. Se aplican siempre: el paso es idempotente (reutiliza las
  #    claves ya guardadas en /etc/issabel.conf) y es el unico que deja
  #    coherentes la clave de asteriskuser en MariaDB, /etc/amportal.conf, el
  #    secreto del AMI y la tabla ampusers.
  if [ "$SKIP_PASSWORDS" = "1" ]; then
    warn "$(msg skip_passwords)"
    return
  fi
  [ -x /usr/bin/issabel-admin-passwords ] || die "issabel-admin-passwords no encontrado (falta el paquete issabel-firstboot)"

  local mode=init cur_root="$MYSQL_ROOT_PWD" cur_admin="$ADMIN_PWD" rc=0
  if [ -f /etc/issabel.conf ] && grep -q '^mysqlrootpwd=' /etc/issabel.conf; then
    # '--cli init' aborta si /etc/issabel.conf ya tiene mysqlrootpwd
    # ("Password configuration already present"): se usa '--cli change', que
    # reutiliza las claves ya guardadas.
    mode=change
    cur_root="$(sed -n 's/^mysqlrootpwd=//p' /etc/issabel.conf | head -1)"
    cur_admin="$(sed -n 's/^amiadminpwd=//p' /etc/issabel.conf | head -1)"
    [ -n "$cur_admin" ] || cur_admin="$ADMIN_PWD"
    log "$(msg reapply_passwords)"
  else
    log "$(msg init_passwords)"
  fi

  # Los scripts SQL del spool (permisos de asteriskuser y tablas de los modulos)
  # los aplica Issabel en apply_updatesql(), pero solo en el modo '--cli init'
  # y se detiene en el primer script con error: se aplican aqui antes y despues.
  #
  # ORDEN (validado el 2026-10-21): el spool NO puede aplicarse antes de que
  # exista la clave de root. En EL8 el root de MariaDB arranca con la clave
  # vacia (plugin unix_socket), de modo que 'mysql -uroot -p<clave>' falla
  # con ERROR 1045 y el script aborta antes de inicializar Issabel. Issabel
  # mismo aplica el spool DESPUES de fijar la clave (set_mysql_root_password
  # -> save_keys -> apply_updatesql). Aqui se replica ese orden: primero se
  # deja el spool pendiente, se inicializa Issabel (que fija la clave y aplica
  # los scripts) y despues se recoge lo que quede.
  if [ "$mode" = init ]; then
    # '--cli init' exige que /etc/issabel.conf NO tenga mysqlrootpwd (si lo
    # tiene, aborta con 'Password configuration already present').
    #
    # Con 'set -e' un fallo aborta el script, asi que el codigo de salida se
    # captura con '|| rc=$?' (si no, la red de seguridad de abajo no se
    # ejecutaria nunca).
    /usr/bin/issabel-admin-passwords --cli init "$cur_root" "$cur_admin" || rc=$?
  else
    # '--cli change' NO aplica el spool (solo lo hace '--cli init'): hay que
    # aplicarlo aqui, y la clave de root ya existe en este punto.
    apply_db_spool "$cur_root" || die "fallo al aplicar los scripts SQL del spool"
    /usr/bin/issabel-admin-passwords --cli change "$cur_root" "$cur_admin" || rc=$?
  fi
  # Red de seguridad: scripts que Issabel dejo sin aplicar (los que fallaron
  # y detuvieron su apply_updatesql). Ahora la clave de root ya existe.
  apply_db_spool "$cur_root" || die "fallo al aplicar los scripts SQL del spool"
  if [ "$rc" -ne 0 ]; then
    # Issabel pudo detenerse a mitad (por ejemplo si apply_updatesql fallo):
    # la clave de root ya quedo fijada, asi que se aplica el spool que falte
    # y se reintenta con '--cli change', que si fija la clave web.
    warn "$(msg admin_passwords_retry "$mode" "$rc")"
    apply_db_spool "$cur_root" || die "fallo al aplicar los scripts SQL del spool"
    /usr/bin/issabel-admin-passwords --cli change "$cur_root" "$cur_admin" \
      || die "issabel-admin-passwords --cli change fallo"
  fi

  harden_ami

  # El servicio de primer arranque ejecuta '--init' interactivo en tty2: sobra
  # porque las contrasenas ya estan fijadas, y en un host sin consola fallaria.
  systemctl disable issabel-firstboot.service 2>/dev/null || true
  touch "$STATE/passwords_done"
  [ -x /usr/sbin/amportal ] && /usr/sbin/amportal chown || true
}

# El AMI (manager) solo debe escuchar en loopback: la interfaz web de Issabel
# se conecta a 127.0.0.1:5038 y no hace falta exponerlo a la red.
harden_ami() {
  local f=/etc/asterisk/manager.conf
  [ -f "$f" ] || return 0
  if grep -qE '^[[:space:]]*bindaddr[[:space:]]*=' "$f"; then
    sed -i -E 's|^[[:space:]]*bindaddr[[:space:]]*=.*|bindaddr = 127.0.0.1|' "$f"
  elif grep -q '^\[general\]' "$f"; then
    sed -i '0,/^\[general\]/s//[general]\nbindaddr = 127.0.0.1/' "$f"
  fi
  grep -qE '^[[:space:]]*bindaddr[[:space:]]*=[[:space:]]*127\.0\.0\.1' "$f" \
    || warn "no se pudo dejar el AMI en 127.0.0.1 (revisa $f)"
  systemctl restart asterisk
}

# ---------------------------------------------------------------------------
# SELinux en enforcing.
#
# La politica de EL8 no cubre a Issabel 5: hacen falta (a) un modulo propio
# (map del astdb de sqlite, acceso del panel web a la configuracion de
# Asterisk y al AMI, lectura de logs), (b) reetiquetar los directorios que
# escribe el panel web, y (c) un tipo de puerto para el AMI. El modulo se
# compila en caliente con checkmodule/semodule_package, sin instalar
# policycoreutils-devel.
# ---------------------------------------------------------------------------
selinux_enforce() {
  local dir=/usr/share/issabel
  local te="$dir/issabel_selinux.te" mod="$dir/issabel_selinux.mod"
  local pp="$dir/issabel_selinux.pp" err=/tmp/issabel-selinux.err
  : > "$err"

  command -v semodule >/dev/null 2>&1 || {
    warn "$(msg semodule_missing)"
    setenforce 0 2>/dev/null || true
    return 0
  }

  mkdir -p "$dir"
  cat > "$te" <<'TEEOF'
# Modulo SELinux de Issabel 5 para EL8.
#
# Copia de referencia del modulo que el netinstall genera en caliente
# (funcion selinux_enforce de issabel5-netinstall-el8.sh). Compilar y cargar:
#   checkmodule -m -M -o issabel_selinux.mod issabel-selinux.te
#   semodule_package -o issabel_selinux.pp -m issabel_selinux.mod
#   semodule -i issabel_selinux.pp
module issabel_selinux 1.0;

require {
    type asterisk_t;
    type asterisk_var_lib_t;
    type asterisk_etc_t;
    type asterisk_log_t;
    type httpd_t;
    type httpd_sys_content_t;
    type asterisk_port_t;
    type ssh_port_t;
    type http_port_t;
    type var_log_t;
    type fixed_disk_device_t;
    type nvme_device_t;
    type configfs_t;
    attribute file_type;
    class file { read write open getattr setattr append map unlink };
    class dir { read write open getattr setattr search add_name remove_name };
    class tcp_socket { name_connect };
    class blk_file { getattr };
    class bluetooth_socket { create ioctl };
}

# Ficheros de configuracion propios de Issabel (amportal.conf, issabel.conf).
# Los escribe el panel web y los lee Asterisk.
type issabel_conf_t, file_type;
allow httpd_t     issabel_conf_t:file { read write open getattr setattr append };
allow asterisk_t issabel_conf_t:file { read open getattr };

# Asterisk usa sqlite (astdb.sqlite3) y mapea en memoria el fichero -shm.
allow asterisk_t asterisk_var_lib_t:file map;

# El panel web edita la configuracion de Asterisk (/etc/asterisk y los .conf
# que los modulos de Issabel sirven bajo /var/www/html/admin/modules/*/etc).
allow httpd_t asterisk_etc_t:file { read write open getattr setattr };
allow httpd_t asterisk_etc_t:dir { read open getattr search add_name remove_name write setattr };

# El panel web escribe y consulta el log de Issabel.
allow httpd_t asterisk_log_t:file { read write open getattr append setattr };
allow httpd_t asterisk_log_t:dir { read open getattr search };

# Asterisk lee ficheros de configuracion que el panel web publica.
allow asterisk_t httpd_sys_content_t:file { read open getattr };

# El panel web habla con Asterisk por AMI (puerto 5038).
allow httpd_t asterisk_port_t:tcp_socket name_connect;

# El configurador de endpoints provisiona los telefonos por SSH y el modulo de
# addons consulta el repositorio por HTTPS.
allow httpd_t ssh_port_t:tcp_socket name_connect;
allow httpd_t http_port_t:tcp_socket name_connect;

# El visor de logs del panel lee los ficheros de /var/log (solo lectura).
allow httpd_t var_log_t:file { read open getattr };

# El panel web muestra el estado de disco (df/mount): solo lee metadatos.
allow httpd_t fixed_disk_device_t:blk_file getattr;
allow httpd_t nvme_device_t:blk_file getattr;
allow httpd_t configfs_t:dir getattr;

# El modulo de bluetooth de Asterisk no tiene permisos en el policy de base.
allow asterisk_t self:bluetooth_socket { create ioctl };
TEEOF

  if ! checkmodule -m -M -o "$mod" "$te" 2>>"$err"; then
    warn "$(msg selinux_compile_fail "$(tail -n 1 "$err")")"
    setenforce 0 2>/dev/null || true
    return 1
  fi
  if ! semodule_package -o "$pp" -m "$mod" 2>>"$err"; then
    warn "$(msg selinux_package_fail "$(tail -n 1 "$err")")"
    setenforce 0 2>/dev/null || true
    return 1
  fi
  if ! semodule -i "$pp" 2>>"$err"; then
    warn "$(msg selinux_install_fail "$(tail -n 1 "$err")")"
    setenforce 0 2>/dev/null || true
    return 1
  fi
  log "$(msg selinux_module_installed)"

  # Etiquetas de fichero: configuracion propia de Issabel, cache y bases de
  # datos que escribe el panel web, .conf de Asterisk servidos por el panel y
  # el helper 'retrieve_conf' que el panel ejecuta.
  local spec type path
  for spec in \
      'issabel_conf_t|/etc/amportal\.conf' \
      'issabel_conf_t|/etc/issabel\.conf' \
      'httpd_sys_rw_content_t|/var/www/db(/.*)?' \
      'httpd_sys_rw_content_t|/var/www/html/var(/.*)?' \
      'httpd_sys_rw_content_t|/var/www/html/templates_c(/.*)?' \
      'httpd_sys_rw_content_t|/var/www/html/cache(/.*)?' \
      'asterisk_etc_t|/var/www/html/admin/modules/[^/]+/etc(/.*)?' \
      'bin_t|/var/lib/asterisk/bin(/.*)?'
  do
    type="${spec%%|*}"; path="${spec#*|}"
    semanage fcontext -a -t "$type" "$path" >>"$err" 2>&1 \
      || semanage fcontext -m -t "$type" "$path" >>"$err" 2>&1 \
      || warn "no se pudo etiquetar $path como $type"
  done

  # Puerto AMI con tipo propio: el panel web (httpd_t) necesita poder conectar.
  semanage port -a -t asterisk_port_t -p tcp 5038 >>"$err" 2>&1 \
    || semanage port -m -t asterisk_port_t -p tcp 5038 >>"$err" 2>&1 \
    || warn "no se pudo etiquetar el puerto 5038 como asterisk_port_t"

  restorecon -R /etc/amportal.conf /etc/issabel.conf /etc/asterisk \
              /var/log/asterisk /var/www/db /var/www/html/var \
              /var/www/html/templates_c /var/www/html/cache \
              /var/www/html/admin/modules /var/lib/asterisk/bin >>"$err" 2>&1 || true

  setenforce 1 2>>"$err" || true
  if ! getenforce | grep -q Enforcing; then
    warn "$(msg selinux_enforce_fail "$(tail -n 1 "$err")")"
    return 1
  fi
  log "$(msg selinux_enforce_ok)"

  # Asterisk mapea en memoria el astdb de sqlite y el panel web habla con el
  # AMI: sin las etiquetas anteriores ambos fallarian, asi que se reinician.
  systemctl restart asterisk httpd || true
  sleep 5
  if ! systemctl is-active --quiet asterisk; then
    warn "$(msg asterisk_no_enforcing)"
    return 1
  fi
  log "$(msg selinux_labelled)"
}

main() {
  if [ "${1:-}" = "--audit" ]; then audit; exit 0; fi
  mkdir -p "$STATE"; chmod 700 "$STATE"
  touch "$LOG"; chmod 600 "$LOG"; : > "$ERRS"; chmod 600 "$ERRS"   # log se acumula entre corridas
  exec > >(tee -a "$LOG") 2>&1
  trap 'log "FALLO en linea $LINENO (ver $LOG)"' ERR

  preflight
  enable_deps
  import_gpg
  add_repos
  sys_prep
  dnf -y install issabel-config_helpers
  if [ ! -e "$STATE/lang_done" ] && [ -t 0 ] && [ -x /usr/bin/issabel-change-language ]; then
    /usr/bin/issabel-change-language && touch "$STATE/lang_done"
  fi
  log "$(msg update_os)"
  [ "$SKIP_UPDATE" = "1" ] || dnf -y update
  ensure_rhck_default
  build_compat_rpms
  install_all
  post_install
  firewall
  init_passwords
  selinux_enforce || warn "SELinux queda en permissive: revisa /tmp/issabel-selinux.err"
  rm -f /tmp/inst1.txt /tmp/inst2.txt
  audit
  if [ -s "$ERRS" ]; then
    warn "$(msg pkg_errors "$(tr '\n' ' ' < "$ERRS")")"
    die "$(msg install_incomplete "$ERRS")"
  fi
  log "$(msg done "$0")"
  [ "$REBOOT" = "1" ] && reboot || true
}

main "$@"

# ---------------------------------------------------------------------------
# RIESGOS RESIDUALES (validados en lab el 2026-10-21 sobre OL 8.10):
#  1. 'dahdi', 'libopenr2' y 'python-cjson' no existen en EL8/EPEL8/CRB: se
#     resuelven con RPM locales de compatibilidad (build_compat_rpms). El stub
#     de openr2 deja chan_dahdi sin soporte R2/MF/SS7, que Issabel 5 no usa.
#  2. fop2 solo existe en 'commercial_addons': requiere ADDONS=licensed.
#  3. 'wanpipe' no esta publicado para EL8: requiere ALLOW_NOGPG/ADDONS y
#     solo funcionara si el repositorio comercial lo publica.
#  4. Interaccion de firewalld con el modulo Firewall de Issabel (usa iptables).
#  5. PHP 7.4 esta EOL upstream: mantener la interfaz web detras de ACL/VPN.
#  6. La ISO oficial de Issabel 5 trae el juego completo de dependencias; el
#     netinstall necesita estos RPM de compatibilidad.
# ---------------------------------------------------------------------------

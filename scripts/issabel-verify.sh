#!/usr/bin/env bash
# issabel-verify.sh - Comprobacion funcional de la instalacion de Issabel 5 en EL8.
#
# Valida el estado real del sistema tras ejecutar issabel5-netinstall-el8.sh:
# servicios, MariaDB, Asterisk/AMI, interfaz web, exposicion de sockets y
# hardening. Devuelve 0 si todo pasa y 1 si algo falla.
#
# Uso:  ./issabel-verify.sh [-v]
#   -v   muestra la salida de los comandos de diagnostico

set -uo pipefail
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0
FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; PASS=$((PASS+1)); }
ko()   { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL+1)); }
head_() { printf '\n== %s ==\n' "$*"; }
run()  { [ "$VERBOSE" = "1" ] && "$@" 2>&1 | sed 's/^/      /'; return 0; }

# Conteo de denegaciones SELinux (asterisk_t / httpd_t) en una ventana
# temporal: se toma una muestra al empezar la comprobacion y otra al
# terminar, para detectar solo las denegaciones nuevas que produce el propio
# test (login web, panel, AMI...).
DEN_SINCE=$(( $(date +%s) - 300 ))
den_count() {
  grep -h 'avc:  denied' /var/log/audit/audit.log 2>/dev/null \
    | awk -v s="$DEN_SINCE" '{ if (match($0, /audit\(([0-9.]+):/, m) && m[1]+0 >= s) print }' \
    | grep -cE 'scontext=[^ ]*(asterisk_t|httpd_t)' || true
}
DEN_START="$(den_count)"

# --- credenciales (las mismas que deja el instalador por defecto) ---------
ROOT_PWD="$(sed -n 's/^mysqlrootpwd=//p' /etc/issabel.conf 2>/dev/null | head -1)"
ADMIN_PWD="$(sed -n 's/^amiadminpwd=//p' /etc/issabel.conf 2>/dev/null | head -1)"
AMP_PWD="$(sed -n 's/^AMPDBPASS=//p' /etc/amportal.conf 2>/dev/null | head -1)"

head_ "1. Servicios"
for s in asterisk mariadb httpd; do
  if systemctl is-active --quiet "$s"; then ok "$s activo"; else ko "$s NO esta activo"; fi
done
if systemctl is-enabled --quiet asterisk; then ok "asterisk habilitado"; else ko "asterisk no esta habilitado"; fi
if systemctl is-enabled --quiet mariadb; then ok "mariadb habilitado"; else ko "mariadb no esta habilitado"; fi

head_ "2. MariaDB"
if [ -n "$ROOT_PWD" ] && MYSQL_PWD="$ROOT_PWD" mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then
  ok "root entra con la clave de /etc/issabel.conf"
else
  ko "root NO entra con la clave de /etc/issabel.conf"
fi
if MYSQL_PWD="$AMP_PWD" mysql -uasteriskuser -e 'SELECT 1' >/dev/null 2>&1; then
  ok "asteriskuser entra con la clave de /etc/amportal.conf"
else
  ko "asteriskuser NO entra con la clave de /etc/amportal.conf (AMPDBPASS desincronizado)"
fi
if MYSQL_PWD="$ROOT_PWD" mysql -uroot -N -e \
     "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='asterisk';" 2>/dev/null \
     | grep -qE '^[0-9]{2,}$'; then
  ok "la BD 'asterisk' tiene el esquema instalado"
else
  ko "la BD 'asterisk' esta vacia o no existe"
fi
if MYSQL_PWD="$ROOT_PWD" mysql -uroot -N -e \
     "SELECT COUNT(*) FROM asterisk.ampusers WHERE username='admin';" 2>/dev/null | grep -q '^1$'; then
  ok "el usuario 'admin' existe en ampusers"
else
  ko "el usuario 'admin' no esta en ampusers"
fi
if [ -n "$ADMIN_PWD" ]; then
  sha="$(printf '%s' "$ADMIN_PWD" | sha1sum | cut -d' ' -f1)"
  stored="$(MYSQL_PWD="$ROOT_PWD" mysql -uroot -N -e \
            "SELECT password_sha1 FROM asterisk.ampusers WHERE username='admin';" 2>/dev/null)"
  if [ "$sha" = "$stored" ]; then
    ok "la clave de admin de la web coincide con ampusers"
  else
    ko "la clave de admin de la web NO coincide con ampusers"
  fi
fi

head_ "3. Asterisk"
if timeout 15 asterisk -rx 'core show uptime' 2>/dev/null | grep -qi 'Uptime'; then
  ok "la CLI de Asterisk responde"
else
  ko "la CLI de Asterisk no responde"
fi
ami_out="$( { printf 'action: login\r\nusername: admin\r\nsecret: %s\r\n\r\naction: ping\r\n\r\n' "$ADMIN_PWD"; sleep 2; } \
           | timeout 15 nc 127.0.0.1 5038 2>/dev/null | tr -d '\r' )"
if printf '%s' "$ami_out" | grep -q 'Authentication accepted' && \
   printf '%s' "$ami_out" | grep -q 'Ping: Pong'; then
  ok "el AMI acepta el login de admin (127.0.0.1:5038)"
else
  ko "el AMI NO acepta el login de admin"
fi
if [ -f /etc/asterisk/extensions.conf ] && grep -q 'extensions_custom' /etc/asterisk/extensions.conf; then
  ok "extensions.conf carga las extensiones"
else
  ko "extensions.conf no incluye extensions_custom.conf"
fi
if timeout 15 asterisk -rx 'core show application' >/dev/null 2>&1; then
  ok "los modulos de Asterisk cargan"
else
  ko "la CLI de Asterisk no responde a 'core show application'"
fi

head_ "4. Interfaz web"
BASE="https://127.0.0.1"
code="$(curl -sk -L -o /dev/null -w '%{http_code}' --max-time 20 "$BASE/")"
case "$code" in
  200) ok "$BASE/ sirve la pagina de entrada ($code)" ;;
  *)   ko "$BASE/ responde $code" ;;
esac
if [ -f /var/www/html/admin/index.php ] && [ -d /var/www/html/admin/modules ]; then
  ok "la interfaz de Issabel esta desplegada en /var/www/html/admin"
else
  ko "falta la interfaz de Issabel en /var/www/html/admin"
fi
# Login real contra la interfaz (no solo un 200 en la pagina de inicio).
jar="$(mktemp)"
if curl -sk -c "$jar" -L --max-time 20 "$BASE/" | grep -qi 'name="input_user"'; then
  ok "la pagina de login de Issabel se sirve"
else
  ko "la pagina de login de Issabel no parece la esperada"
fi
if [ -n "$ADMIN_PWD" ]; then
  login="$(curl -sk -b "$jar" -c "$jar" --max-time 25 \
            --data-urlencode "submit_login=1" \
            --data-urlencode "input_user=admin" \
            --data-urlencode "input_pass=$ADMIN_PWD" \
            -o /dev/null -w '%{http_code}' \
            "$BASE/index.php")"
  if [ "$login" = "302" ] && grep -q issabelSession "$jar"; then
    ok "el login de la interfaz web es correcto (admin)"
  else
    ko "el login de la interfaz web no funciono (http=$login)"
  fi
  panel="$(curl -sk -b "$jar" --max-time 25 -o /tmp/issabel-panel.html -w '%{http_code}' \
           "$BASE/admin/config.php")"
  if [ "$panel" = "200" ] && grep -qi 'IssabelPBX' /tmp/issabel-panel.html; then
    ok "el panel IssabelPBX se carga con la sesion de admin"
  else
    ko "el panel IssabelPBX no se carga (http=$panel)"
  fi
else
  ko "no se pudo leer la clave de admin para probar el login"
fi
rm -f "$jar"

head_ "5. Exposicion de sockets"
for p in 3306 5038; do
  outside="$(ss -H -tln | awk -v p=":$p" '$4 ~ p"$"' | awk '{print $4}' \
            | grep -vE '^(127\.0\.0\.1|\[::1\]):' | tr '\n' ' ')"
  if [ -z "$outside" ]; then
    ok "el puerto $p solo escucha en loopback"
  else
    ko "el puerto $p escucha fuera de loopback: $outside"
  fi
done

head_ "6. Hardening y limpieza"
if [ -f /etc/my.cnf.d/zz-issabel-hardening.cnf ] && \
   [ "$(stat -c '%a' /etc/my.cnf.d/zz-issabel-hardening.cnf)" = "644" ]; then
  ok "el .cnf de MariaDB es legible por el usuario mysql"
else
  ko "el .cnf de MariaDB no es legible por el usuario mysql (bind-address se ignora)"
fi
if grep -qE '^[[:space:]]*bindaddr[[:space:]]*=[[:space:]]*127\.0\.0\.1' /etc/asterisk/manager.conf; then
  ok "el AMI escucha solo en 127.0.0.1"
else
  ko "el AMI no esta limitado a 127.0.0.1"
fi
if systemctl is-enabled --quiet issabel-firstboot.service 2>/dev/null; then
  ko "issabel-firstboot sigue habilitado (arrancaria el modo interactivo)"
else
  ok "issabel-firstboot deshabilitado (sin consola no se queda colgado)"
fi
left="$(find /var/spool/issabel-mysqldbscripts -type f 2>/dev/null | wc -l)"
if [ "$left" -eq 0 ]; then
  ok "no quedan scripts SQL del spool sin aplicar"
else
  ko "quedan $left scripts SQL del spool sin aplicar"
fi
if getenforce 2>/dev/null | grep -q Enforcing; then
  ok "SELinux en modo enforcing"
else
  ko "SELinux no esta en enforcing ($(getenforce 2>/dev/null))"
fi
if semodule -l 2>/dev/null | grep -q '^issabel_selinux'; then
  ok "el modulo SELinux de Issabel esta instalado"
else
  ko "falta el modulo SELinux 'issabel_selinux'"
fi
if semanage port -l 2>/dev/null | grep -qE 'asterisk_port_t[[:space:]]+tcp[[:space:]]+.*\b5038\b'; then
  ok "el puerto AMI 5038 tiene el tipo asterisk_port_t"
else
  ko "el puerto 5038 no esta etiquetado como asterisk_port_t"
fi
since=$(( $(date +%s) - 600 ))
den_now="$(den_count)"
new_den=$(( ${den_now:-0} - ${DEN_START:-0} ))
if [ "$new_den" -le 0 ]; then
  ok "sin denegaciones SELinux nuevas de asterisk/httpd durante la comprobacion"
else
  ko "$new_den denegaciones SELinux nuevas de asterisk/httpd durante la comprobacion"
fi
if systemctl is-active --quiet firewalld; then
  ok "firewalld activo"
else
  ko "firewalld no esta activo"
fi
if [ -f /var/lib/issabel-netinstall/passwords_done ]; then
  ok "la marca de instalacion completada existe"
else
  ko "falta la marca /var/lib/issabel-netinstall/passwords_done"
fi

printf '\n== Resultado ==\n  PASS: %d   FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0

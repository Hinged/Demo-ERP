#!/usr/bin/env bash
#
# Clinic BD - full stack bootstrap
# Target: Ubuntu 22.04 / 24.04, bare metal, VPS, or WSL2 on Windows.
# Run as a normal user with sudo rights. NOT as root.
#
# What it does:
#   1. Installs system packages (MariaDB, Redis, Node, wkhtmltopdf, Bangla fonts)
#   2. Installs frappe-bench and initialises a bench on Frappe v15
#   3. Fetches ERPNext + Frappe Health (version-15)
#   4. Installs the clinic_bd app (expects the clinic_bd/ folder NEXT TO this script)
#   5. Creates a site: clinic.localhost
#
# Honest expectations: 20-40 minutes, needs ~4 GB RAM and ~10 GB disk.
# The asset build step (yarn) is the slow part. If it fails midway, fix the
# reported issue and re-run the failed command manually - the script is
# written so each stage is a plain command you can copy-paste.

set -euo pipefail

if [ "$(id -u)" = "0" ]; then
  echo "Run this as a normal user with sudo, not as root (bench refuses root)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_NAME="clinic.localhost"
BENCH_DIR="$HOME/frappe-bench"

echo "== Clinic BD bootstrap =="
read -rsp "Choose a MariaDB root password: " DB_ROOT_PASS; echo
read -rsp "Choose an Administrator password for the site: " ADMIN_PASS; echo

# ---------------------------------------------------------------- packages --
echo "== [1/6] System packages =="
sudo apt-get update -y
sudo apt-get install -y \
  git curl build-essential pkg-config \
  python3-dev python3-pip python3-venv \
  redis-server mariadb-server mariadb-client libmariadb-dev \
  wkhtmltopdf xvfb fonts-noto-core fonts-beng \
  cron nodejs npm

# Frappe v15 needs Node >= 18. Ubuntu 24.04 ships 18; 22.04 ships 12.
NODE_MAJOR="$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/' || echo 0)"
if [ "${NODE_MAJOR}" -lt 18 ]; then
  echo "Node ${NODE_MAJOR} is too old - installing Node 18 via nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install 18
  nvm alias default 18
fi
sudo npm install -g yarn

# ----------------------------------------------------------------- mariadb --
echo "== [2/6] MariaDB configuration =="
sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<'CNF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
CNF
sudo systemctl restart mariadb || sudo service mariadb restart

# Fresh Ubuntu installs use socket auth for root; switch to password auth
# so bench can create site databases.
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}'); FLUSH PRIVILEGES;" \
  || echo "Root password may already be set - continuing."

# ------------------------------------------------------------------- bench --
echo "== [3/6] frappe-bench =="
python3 -m pip install --user --upgrade frappe-bench --break-system-packages 2>/dev/null \
  || python3 -m pip install --user --upgrade frappe-bench
export PATH="$HOME/.local/bin:$PATH"

if [ ! -d "$BENCH_DIR" ]; then
  bench init "$BENCH_DIR" --frappe-branch version-15
fi
cd "$BENCH_DIR"

# -------------------------------------------------------------------- apps --
echo "== [4/6] Fetching ERPNext and Frappe Health =="
[ -d apps/erpnext ]    || bench get-app erpnext --branch version-15
[ -d apps/healthcare ] || bench get-app health https://github.com/frappe/health --branch version-15 \
  || bench get-app health https://github.com/frappe/health

echo "== [5/6] Installing the clinic_bd app from ${SCRIPT_DIR}/clinic_bd =="
if [ ! -d "${SCRIPT_DIR}/clinic_bd" ]; then
  echo "Could not find clinic_bd/ next to this script. Unzip clinic_bd.zip here first."
  exit 1
fi
[ -d apps/clinic_bd ] || bench get-app "${SCRIPT_DIR}/clinic_bd"

# -------------------------------------------------------------------- site --
echo "== [6/6] Creating site ${SITE_NAME} =="
if [ ! -d "sites/${SITE_NAME}" ]; then
  bench new-site "${SITE_NAME}" \
    --db-root-password "${DB_ROOT_PASS}" \
    --admin-password "${ADMIN_PASS}"
fi
for app in erpnext healthcare clinic_bd; do
  if ! bench --site "${SITE_NAME}" install-app "$app"; then
    echo "WARNING: install-app $app exited non-zero. 'Already installed' is fine on a"
    echo "         re-run; anything else, scroll up and fix it before continuing."
  fi
done
bench use "${SITE_NAME}"

echo
echo "================================================================"
echo " Done. Start the dev server with:"
echo "   cd ${BENCH_DIR} && bench start"
echo " Then open:  http://${SITE_NAME}:8000"
echo " Login:      Administrator / (the password you chose)"
echo " First run shows a setup wizard: country Bangladesh, currency BDT,"
echo " company = your clinic's name."
echo "================================================================"

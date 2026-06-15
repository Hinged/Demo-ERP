# Clinic BD — Session Log

**Date:** 2026-06-15
**Repository:** `Hinged/Demo-ERP`
**Working branch:** `claude/affectionate-bohr-4lhclk`
**Pull request:** [#1 — Add Clinic BD v0.1: Frappe overlay app, bootstrap script, and guide](https://github.com/Hinged/Demo-ERP/pull/1) (draft)

---

## 1. What was requested

A zip file was uploaded containing documents for creating a custom ERP for hospitals and
clinics, with a request to review it and help with the code. The package turned out to be
**Clinic BD v0.1** — a Bangladesh-focused clinic management product built as a custom Frappe
app layered on top of ERPNext + Frappe Health.

Follow-up requests in the session:
1. Review the package and help with the code → import, review, fix, push, open a PR.
2. Explain how to install the Claude Code GitHub App.
3. Create a working GitHub Actions workflow (the repo had an invalid stub).
4. Create this markdown log of the session, including all code written.

---

## 2. What was in the package

Three top-level items:

| Item | Purpose |
| --- | --- |
| `clinic_bd.zip` | The actual product: a custom Frappe app that installs on top of ERPNext + Frappe Health and never touches their core code |
| `setup.sh` | A bootstrap script that builds the whole stack on a fresh Ubuntu machine |
| `GETTING_STARTED.md` | Setup guide, an 8-step end-to-end smoke test, code map, and a Phase 2 backlog |

The app's working features (all implemented as fixtures/hooks/reports, no core edits):

- **Custom fields** — NID number + Bangla name on Patient; BMDC registration number + a
  printable degree summary on Healthcare Practitioner.
- **"Clinic Prescription" print format** for Patient Encounter, laid out like a standard Dhaka
  chamber prescription, set as the doctype default automatically on install.
- **"Medicines Expiring Soon" report** — batches with stock on hand expiring within N days,
  filterable by warehouse (negative "days left" = already expired).
- **Starter Bangla translations** (`translations/bn.csv`) demonstrating the localization
  mechanism.

The architecture is sound: the overlay approach (custom fields + fixtures + hooks only) means
upstream ERPNext / Frappe Health updates stay clean.

---

## 3. Review findings (bugs fixed)

During review I validated all Python (compiles), JSON (parses), the Jinja template (parses),
and `bash -n` on the script, and confirmed `print_format.json`'s embedded HTML is
byte-identical to `prescription_source.html`. I found and fixed four correctness issues plus
some completeness gaps.

### 3.1 `setup.sh` installer-killing typo (critical)

The script installed the apt package `fonts-noto-bengali`, **which does not exist** (verified
against the live Ubuntu 24.04 package index — only `fonts-noto-core` and `fonts-beng` exist).
Because the script runs under `set -euo pipefail`, this aborted the entire 20–40 minute
bootstrap at step 1. Replaced with the two real packages. Also made `install-app` failures
visible instead of swallowing them with `|| true`.

### 3.2 Default print-format hook ran too early

`hooks.py` used `after_install` to point Patient Encounter's default print format at "Clinic
Prescription". But in Frappe v15 an app's fixtures are synced **after** `after_install` fires —
so at that moment the print format doesn't exist yet. It only appeared to work because property
setters don't validate their value. Moved the logic to the `after_sync` hook (runs after
fixtures land) and dropped a redundant manual `frappe.db.commit()`.

### 3.3 Report hygiene

- The report's JSON was missing standard Report metadata (`modified`, `owner`, `docstatus`,
  `idx`, …) that Frappe uses to decide when to re-sync standard reports on `bench migrate`.
  Added the conventional set.
- A `days = 0` filter (meaning "show what's already expired or due today") was silently turned
  into 90 via `int(filters.get("days") or 90)`. Now honored with an explicit
  None/empty-string check and `cint`.
- Passed `item_code` to ERPNext's `get_batch_qty`, saving one DB lookup per batch.

### 3.4 Completeness gaps

- Added the actual **GPL-3.0 license text** (`clinic_bd/license.txt`) — the app declared the
  license but didn't ship it (fetched from the SPDX license-list mirror).
- Added a **root `README.md`** and **`.gitignore`**.
- Filled in `you@example.com` placeholders with the real publisher email.
- Updated one paragraph in `GETTING_STARTED.md` to reflect the repo layout.

Things checked and found **correct** (no change needed): the fixture field names against
Frappe Health v15 doctypes (`complaint`, `medication`, `lab_test_name`, etc. — the template's
fallback chains are smart), the `bench get-app`/`new-site` flags, and the report's defensive
handling of `get_batch_qty` return shapes.

---

## 4. Code written / modified

> All embedded files below are shown in their **final committed state**.

### 4.1 `setup.sh` (modified)

````bash
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
````

### 4.2 `clinic_bd/clinic_bd/hooks.py` (modified)

````python
app_name = "clinic_bd"
app_title = "Clinic BD"
app_publisher = "Syed"
app_description = "Bangladesh-focused clinic management layer on top of ERPNext + Frappe Health"
app_email = "farabeexr@gmail.com"
app_license = "gpl-3.0"

# Both must already be installed on the site before clinic_bd.
required_apps = ["erpnext", "healthcare"]

# Runs during `bench --site <site> install-app clinic_bd`, after this app's
# fixtures are synced. (after_install would fire before the Clinic Prescription
# print format fixture exists in the database.)
after_sync = "clinic_bd.install.after_sync"

# Anything matching these filters is exported with `bench export-fixtures`
# and re-created automatically on every fresh install. This is how the app
# ships its customizations without ever touching ERPNext/Frappe Health core.
fixtures = [
    {"dt": "Custom Field", "filters": [["module", "=", "Clinic BD"]]},
    {"dt": "Print Format", "filters": [["module", "=", "Clinic BD"]]},
]
````

### 4.3 `clinic_bd/clinic_bd/install.py` (rewritten)

````python
import frappe


def after_sync():
    """Runs on install after this app's fixtures are synced, so the
    'Clinic Prescription' print format already exists when we point
    the doctype default at it."""
    set_default_prescription_print_format()


def set_default_prescription_print_format():
    """Make 'Clinic Prescription' the default print format for Patient Encounter,
    so the print button produces our layout without any manual setup."""
    try:
        from frappe.custom.doctype.property_setter.property_setter import (
            make_property_setter,
        )

        make_property_setter(
            "Patient Encounter",
            None,
            "default_print_format",
            "Clinic Prescription",
            "Data",
            for_doctype=True,
            validate_fields_for_doctype=False,
        )
    except Exception:
        # Never block installation over a cosmetic default; just log it.
        frappe.log_error(
            frappe.get_traceback(),
            "clinic_bd: could not set default print format",
        )
````

### 4.4 `clinic_bd/clinic_bd/clinic_bd/report/medicines_expiring_soon/medicines_expiring_soon.py` (modified)

````python
import frappe
from frappe import _
from frappe.utils import add_days, cint, date_diff, nowdate


def execute(filters=None):
    filters = frappe._dict(filters or {})
    # 0 is a valid choice ("already due today or expired"), so only fall
    # back to 90 when the filter is actually absent.
    days = filters.get("days")
    days = 90 if days in (None, "") else cint(days)
    return get_columns(), get_data(days, filters.get("warehouse"))


def get_columns():
    return [
        {"fieldname": "item_code", "label": _("Item"), "fieldtype": "Link", "options": "Item", "width": 140},
        {"fieldname": "item_name", "label": _("Item Name"), "fieldtype": "Data", "width": 200},
        {"fieldname": "batch_no", "label": _("Batch"), "fieldtype": "Link", "options": "Batch", "width": 150},
        {"fieldname": "warehouse", "label": _("Warehouse"), "fieldtype": "Link", "options": "Warehouse", "width": 160},
        {"fieldname": "qty", "label": _("Qty On Hand"), "fieldtype": "Float", "width": 110},
        {"fieldname": "expiry_date", "label": _("Expiry Date"), "fieldtype": "Date", "width": 110},
        {"fieldname": "days_left", "label": _("Days Left"), "fieldtype": "Int", "width": 90},
    ]


def get_data(days, warehouse=None):
    # erpnext's own helper computes batch-wise stock correctly on every
    # supported version, including the v15 serial/batch bundle rework.
    from erpnext.stock.doctype.batch.batch import get_batch_qty

    limit_date = add_days(nowdate(), days)

    batches = frappe.get_all(
        "Batch",
        filters=[
            ["expiry_date", "is", "set"],
            ["expiry_date", "<=", limit_date],
            ["disabled", "=", 0],
        ],
        fields=["name", "item", "expiry_date"],
        order_by="expiry_date asc",
    )

    rows = []
    for batch in batches:
        # Passing item_code spares the helper a per-batch lookup of its item.
        qty_by_warehouse = get_batch_qty(batch_no=batch.name, item_code=batch.item) or []

        # Older versions return a plain number when only batch_no is passed.
        if isinstance(qty_by_warehouse, (int, float)):
            qty_by_warehouse = [{"warehouse": None, "qty": qty_by_warehouse}]

        for entry in qty_by_warehouse:
            qty = entry.get("qty") or 0
            if qty <= 0:
                continue
            if warehouse and entry.get("warehouse") != warehouse:
                continue

            rows.append(
                {
                    "item_code": batch.item,
                    "item_name": frappe.get_cached_value("Item", batch.item, "item_name")
                    if batch.item
                    else None,
                    "batch_no": batch.name,
                    "warehouse": entry.get("warehouse"),
                    "qty": qty,
                    "expiry_date": batch.expiry_date,
                    # Negative means the batch has already expired.
                    "days_left": date_diff(batch.expiry_date, nowdate()),
                }
            )

    return rows
````

### 4.5 `clinic_bd/clinic_bd/clinic_bd/report/medicines_expiring_soon/medicines_expiring_soon.json` (rewritten)

````json
{
 "add_total_row": 0,
 "columns": [],
 "creation": "2026-06-10 00:00:00.000000",
 "disable_prepared_report": 0,
 "disabled": 0,
 "docstatus": 0,
 "doctype": "Report",
 "filters": [],
 "idx": 0,
 "is_standard": "Yes",
 "modified": "2026-06-10 00:00:00.000000",
 "modified_by": "Administrator",
 "module": "Clinic BD",
 "name": "Medicines Expiring Soon",
 "owner": "Administrator",
 "ref_doctype": "Batch",
 "report_name": "Medicines Expiring Soon",
 "report_type": "Script Report",
 "roles": [
  {"role": "System Manager"},
  {"role": "Stock User"},
  {"role": "Stock Manager"},
  {"role": "Healthcare Administrator"}
 ]
}
````

### 4.6 `clinic_bd/pyproject.toml` (modified — email)

````toml
[project]
name = "clinic_bd"
authors = [
    { name = "Syed", email = "farabeexr@gmail.com" },
]
description = "Bangladesh-focused clinic management layer on top of ERPNext + Frappe Health"
requires-python = ">=3.10"
readme = "README.md"
dynamic = ["version"]

[build-system]
requires = ["flit_core >=3.4,<4"]
build-backend = "flit_core.buildapi"

[tool.bench.dev-dependencies]
````

### 4.7 `README.md` (new — repo root)

`````markdown
# Demo-ERP — Clinic BD

A custom ERP for small hospitals and clinics in Bangladesh, built as a thin overlay app
(`clinic_bd/`) on top of [ERPNext](https://github.com/frappe/erpnext) +
[Frappe Health](https://github.com/frappe/health) on Frappe Framework v15. Core apps are
never modified — everything ships as custom fields, fixtures, reports, and hooks, so
upstream updates stay clean.

## What's in this repo

| Path | What it is |
| --- | --- |
| `clinic_bd/` | The Frappe app: NID + Bangla-name fields on Patient, BMDC reg. no + degrees on Healthcare Practitioner, the "Clinic Prescription" print format (default on install), the "Medicines Expiring Soon" report, and starter Bangla translations |
| `setup.sh` | One-shot bootstrap for fresh Ubuntu 22.04/24.04 (bare metal, VPS, or WSL2): MariaDB, Redis, frappe-bench, ERPNext, Frappe Health, this app, and a `clinic.localhost` site |
| `GETTING_STARTED.md` | Environment options, the 8-step end-to-end smoke test, a map of the code for Phase 2, and the prioritized backlog |

## Quick start

    git clone <this-repo> && cd Demo-ERP
    chmod +x setup.sh
    ./setup.sh                          # 20-40 minutes; needs ~4 GB RAM
    cd ~/frappe-bench && bench start    # then open http://clinic.localhost:8000

Read `GETTING_STARTED.md` first — it walks the whole loop from install to a printed
prescription and an expiry report.

## License

GPL-3.0 (see `clinic_bd/license.txt`), matching the apps this extends.
`````

### 4.8 `.gitignore` (new)

````gitignore
__pycache__/
*.pyc
*.egg-info/
build/
dist/
node_modules/
.DS_Store
.vscode/
.idea/
*.swp
````

### 4.9 `.github/workflows/claude.yml` (new — replaces the invalid `main.yml`)

The repo's `main` branch contained a `main.yml` that was only a two-line step fragment with
no `on:` trigger or `jobs:` block — GitHub flags that as an invalid workflow and never runs
it. This replaces it with the standard `anthropics/claude-code-action@v1` setup.

````yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    # Only run when someone mentions @claude in an issue, comment, or review
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read # lets Claude read CI results on PRs
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          # Claude Pro/Max subscribers can authenticate with an OAuth token
          # instead of an API key:
          #   1. run `claude setup-token` on your machine
          #   2. save the result as repo secret CLAUDE_CODE_OAUTH_TOKEN
          #   3. replace the anthropic_api_key line above with:
          # claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
````

### 4.10 `GETTING_STARTED.md` (one paragraph changed)

Section 3 ("Install the stack") originally said to put `setup.sh` and the unzipped folder side
by side in the home directory. It now reflects the repo layout:

> Clone this repository (or copy it) into your home directory — `setup.sh` and the `clinic_bd/`
> folder must sit side by side, which is exactly how the repo is laid out. Then, from the
> repo root:
>
>     chmod +x setup.sh
>     ./setup.sh

### 4.11 `clinic_bd/license.txt` (new)

The full **GNU General Public License v3.0** text (≈674 lines), fetched verbatim from the SPDX
license-list mirror. Not reproduced here for length; it is the standard, unmodified GPL-3.0.

---

## 5. Unchanged files from the original package (for reference)

These shipped in `clinic_bd.zip` and were reviewed but not changed (other than a trailing
newline normalization on `modules.txt`).

### 5.1 `clinic_bd/clinic_bd/clinic_bd/report/medicines_expiring_soon/medicines_expiring_soon.js`

````javascript
frappe.query_reports["Medicines Expiring Soon"] = {
	filters: [
		{
			fieldname: "days",
			label: __("Expiring Within (Days)"),
			fieldtype: "Int",
			default: 90,
			reqd: 1,
		},
		{
			fieldname: "warehouse",
			label: __("Warehouse"),
			fieldtype: "Link",
			options: "Warehouse",
		},
	],
};
````

### 5.2 `clinic_bd/clinic_bd/fixtures/custom_field.json`

````json
[
 {
  "doctype": "Custom Field",
  "name": "Patient-nid_number",
  "dt": "Patient",
  "fieldname": "nid_number",
  "label": "NID Number",
  "fieldtype": "Data",
  "insert_after": "mobile",
  "module": "Clinic BD",
  "translatable": 0,
  "description": "Bangladesh National ID. Optional, but useful for unambiguous patient lookup."
 },
 {
  "doctype": "Custom Field",
  "name": "Patient-patient_name_bangla",
  "dt": "Patient",
  "fieldname": "patient_name_bangla",
  "label": "Patient Name (Bangla)",
  "fieldtype": "Data",
  "insert_after": "last_name",
  "module": "Clinic BD",
  "translatable": 0,
  "description": "Shown on the printed prescription when filled in."
 },
 {
  "doctype": "Custom Field",
  "name": "Healthcare Practitioner-bmdc_reg_no",
  "dt": "Healthcare Practitioner",
  "fieldname": "bmdc_reg_no",
  "label": "BMDC Registration No",
  "fieldtype": "Data",
  "insert_after": "image",
  "module": "Clinic BD",
  "translatable": 0,
  "description": "Bangladesh Medical & Dental Council registration number, printed on prescriptions."
 },
 {
  "doctype": "Custom Field",
  "name": "Healthcare Practitioner-degree_summary",
  "dt": "Healthcare Practitioner",
  "fieldname": "degree_summary",
  "label": "Degrees (printed on prescription)",
  "fieldtype": "Small Text",
  "insert_after": "bmdc_reg_no",
  "module": "Clinic BD",
  "translatable": 0,
  "description": "e.g. MBBS (DU), FCPS (Medicine) - appears under the doctor's name on the prescription."
 }
]
````

### 5.3 `clinic_bd/clinic_bd/fixtures/prescription_source.html`

This is the editable source of the print format; `print_format.json` embeds an identical copy
in its `html` field (verified byte-for-byte).

`````html
{%- set bmdc = frappe.db.get_value("Healthcare Practitioner", doc.practitioner, "bmdc_reg_no") if doc.practitioner else None -%}
{%- set degrees = frappe.db.get_value("Healthcare Practitioner", doc.practitioner, "degree_summary") if doc.practitioner else None -%}
{%- set bangla_name = frappe.db.get_value("Patient", doc.patient, "patient_name_bangla") if doc.patient else None -%}
{%- set nid = frappe.db.get_value("Patient", doc.patient, "nid_number") if doc.patient else None -%}
<style>
  .rx-root { font-family: 'Noto Sans Bengali', 'SolaimanLipi', 'Kalpurush', Arial, sans-serif; font-size: 12px; color: #1a1a1a; line-height: 1.55; }
  .rx-root table { width: 100%; border-collapse: collapse; }
  .rx-head td { vertical-align: top; padding-bottom: 8px; }
  .rx-doctor { font-size: 16px; font-weight: bold; }
  .rx-muted { color: #444; font-size: 11px; }
  .rx-clinic { text-align: right; }
  .rx-clinic .rx-clinic-name { font-size: 15px; font-weight: bold; }
  .rx-patient { border-top: 1.5px solid #1a1a1a; border-bottom: 1px solid #888; }
  .rx-patient td { padding: 5px 4px; font-size: 12px; }
  .rx-body td { vertical-align: top; }
  .rx-left { width: 32%; border-right: 1px solid #bbb; padding: 10px 12px 10px 0; }
  .rx-right { width: 68%; padding: 10px 0 10px 16px; }
  .rx-section-title { font-size: 11px; font-weight: bold; letter-spacing: 0.06em; text-transform: uppercase; color: #555; margin: 10px 0 3px; }
  .rx-symbol { font-size: 26px; font-weight: bold; margin: 0 0 6px; }
  .rx-drug { margin: 0 0 12px; }
  .rx-drug .rx-drug-name { font-size: 13px; font-weight: bold; }
  .rx-drug .rx-drug-detail { margin-left: 18px; color: #222; }
  ul.rx-list { margin: 0; padding-left: 16px; }
  .rx-footer { margin-top: 28px; }
  .rx-sign { border-top: 1px solid #1a1a1a; width: 220px; padding-top: 4px; font-size: 11px; }
</style>

<div class="rx-root">

  <table class="rx-head">
    <tr>
      <td>
        <div class="rx-doctor">{{ doc.get("practitioner_name") or doc.get("practitioner") or "" }}</div>
        {% if degrees %}<div class="rx-muted">{{ degrees }}</div>{% endif %}
        {% if doc.get("medical_department") %}<div class="rx-muted">{{ doc.medical_department }}</div>{% endif %}
        {% if bmdc %}<div class="rx-muted">BMDC Reg. No: {{ bmdc }}</div>{% endif %}
      </td>
      <td class="rx-clinic">
        <div class="rx-clinic-name">{{ doc.get("company") or "" }}</div>
        <div class="rx-muted">{{ frappe.utils.formatdate(doc.encounter_date, "dd-MM-yyyy") if doc.get("encounter_date") else "" }}
          {%- if doc.get("encounter_time") %} &nbsp;|&nbsp; {{ doc.encounter_time }}{% endif %}</div>
        <div class="rx-muted">Encounter: {{ doc.name }}</div>
      </td>
    </tr>
  </table>

  <table class="rx-patient">
    <tr>
      <td><b>Patient:</b> {{ doc.get("patient_name") or "" }}{% if bangla_name %} ({{ bangla_name }}){% endif %}</td>
      <td><b>Age:</b> {{ doc.get("patient_age") or "-" }}</td>
      <td><b>Sex:</b> {{ doc.get("patient_sex") or "-" }}</td>
      <td><b>ID:</b> {{ doc.get("patient") or "" }}{% if nid %} / NID: {{ nid }}{% endif %}</td>
    </tr>
  </table>

  <table class="rx-body">
    <tr>
      <td class="rx-left">
        {% if doc.get("symptoms") %}
          <div class="rx-section-title">Chief complaints</div>
          <ul class="rx-list">
            {% for row in doc.symptoms %}<li>{{ row.get("symptom") or row.get("complaint") or "" }}</li>{% endfor %}
          </ul>
        {% endif %}

        {% if doc.get("diagnosis") %}
          <div class="rx-section-title">Diagnosis</div>
          <ul class="rx-list">
            {% for row in doc.diagnosis %}<li>{{ row.get("diagnosis") or "" }}</li>{% endfor %}
          </ul>
        {% endif %}

        {% if doc.get("lab_test_prescription") %}
          <div class="rx-section-title">Investigations</div>
          <ul class="rx-list">
            {% for row in doc.lab_test_prescription %}<li>{{ row.get("lab_test_name") or row.get("lab_test_code") or "" }}</li>{% endfor %}
          </ul>
        {% endif %}
      </td>

      <td class="rx-right">
        <div class="rx-symbol">Rx</div>
        {% if doc.get("drug_prescription") %}
          {% for row in doc.drug_prescription %}
            <div class="rx-drug">
              <div class="rx-drug-name">{{ loop.index }}. {{ row.get("drug_name") or row.get("medication") or row.get("drug_code") or "" }}
                {%- if row.get("dosage_form") %} <span style="font-weight:normal;">({{ row.dosage_form }})</span>{% endif %}</div>
              <div class="rx-drug-detail">
                {{ row.get("dosage") or "" }}{% if row.get("period") %} &mdash; {{ row.period }}{% endif %}
                {% if row.get("comment") %}<br><i>{{ row.comment }}</i>{% endif %}
              </div>
            </div>
          {% endfor %}
        {% endif %}

        {% if doc.get("encounter_comment") %}
          <div class="rx-section-title">Advice</div>
          <div>{{ doc.encounter_comment }}</div>
        {% endif %}
      </td>
    </tr>
  </table>

  <table class="rx-footer">
    <tr>
      <td></td>
      <td style="width: 240px;">
        <div class="rx-sign">
          {{ doc.get("practitioner_name") or "" }}{% if bmdc %}<br>BMDC Reg. No: {{ bmdc }}{% endif %}
        </div>
      </td>
    </tr>
  </table>

</div>
`````

### 5.4 `clinic_bd/clinic_bd/translations/bn.csv`

````csv
Patient,রোগী
Doctor,ডাক্তার
Appointment,অ্যাপয়েন্টমেন্ট
Prescription,ব্যবস্থাপত্র
Medicine,ওষুধ
Warehouse,গুদাম
Expiry Date,মেয়াদ উত্তীর্ণের তারিখ
````

### 5.5 Other app scaffolding

| File | Content |
| --- | --- |
| `clinic_bd/clinic_bd/__init__.py` | `__version__ = "0.1.0"` |
| `clinic_bd/clinic_bd/modules.txt` | `Clinic BD` |
| `clinic_bd/clinic_bd/patches.txt` | (empty) |
| `clinic_bd/clinic_bd/config/__init__.py` | (empty) |
| `clinic_bd/clinic_bd/templates/__init__.py` | (empty) |
| `clinic_bd/clinic_bd/templates/pages/__init__.py` | (empty) |
| `clinic_bd/clinic_bd/public/.gitkeep` | (empty) |
| `clinic_bd/clinic_bd/clinic_bd/__init__.py` | (empty) |
| `clinic_bd/clinic_bd/clinic_bd/report/__init__.py` | (empty) |
| `clinic_bd/clinic_bd/clinic_bd/report/medicines_expiring_soon/__init__.py` | (empty) |
| `clinic_bd/README.md` | App-level readme (feature summary + install commands) |

---

## 6. Git & PR workflow

The session hit a snag worth recording: the first several push attempts failed with
`403 ... Permission to Hinged/Demo-ERP.git denied` and `Resource not accessible by integration`.
This was **not** a network issue — reads worked only because the repo is public, while the
Claude GitHub App lacked write access. After the app was granted access:

1. A `main` branch had appeared on the remote (a "Create main.yml" commit). Instead of pushing
   a placeholder base, the work was rebased onto the user's `main` and squashed into a single
   clean commit.
2. `claude/affectionate-bohr-4lhclk` was pushed (26 files; `setup.sh` keeps its executable bit).
3. Draft **PR #1** was opened against `main`.
4. The invalid `main.yml` was replaced by `claude.yml` in a follow-up commit on the same branch.

Commits on the branch:

````text
d73ff7d Replace stub main.yml with a working Claude Code workflow
d7570d7 Add Clinic BD v0.1: Frappe overlay app, bootstrap script, and guide
a266e8e Create main.yml   (pre-existing on main)
````

---

## 7. What's left for the user

1. **Set the Actions secret** so the workflow can authenticate: repo **Settings → Secrets and
   variables → Actions → New repository secret**, name it `ANTHROPIC_API_KEY` (from
   [console.anthropic.com](https://console.anthropic.com)). Pro/Max subscribers can instead use
   `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` — see the comment in `claude.yml`.
2. **Review and merge PR #1.**
3. **Run the smoke test** (`GETTING_STARTED.md` §4): clone on an Ubuntu/WSL2 box, `./setup.sh`,
   then walk the 8 steps until you get a printed prescription and the expiry report. That is the
   acceptance gate before touching the Phase 2 backlog.

### Phase 2 backlog (from `GETTING_STARTED.md`, in priority order)

1. Full Bangla print — collect real clinic phrases, extend `bn.csv` and the prescription layout.
2. A reorder-shortage report (same template as the expiry report, driven by Item reorder levels).
3. Simplified roles — a Receptionist who can register patients and book appointments but not
   open clinical notes.
4. A one-page "daily collections" report for the owner.
5. SMS appointment reminders via a local gateway — only after a pilot clinic asks.

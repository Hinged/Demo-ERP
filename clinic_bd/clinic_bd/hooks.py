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

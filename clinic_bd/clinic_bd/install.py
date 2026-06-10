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

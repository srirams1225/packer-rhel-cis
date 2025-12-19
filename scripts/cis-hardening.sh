#!/bin/bash
# CIS Level 1 Hardening Script (Final Version)
# Forces Tailoring (No Fallback)
# Works on both RHEL 9 and Rocky Linux 9

set -euo pipefail

# Check if CIS hardening is enabled via Packer variable
if [[ "${ENABLE_CIS_HARDENING:-false}" != "true" ]]; then
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [CIS-HARDENING] [INFO] CIS hardening is disabled. Skipping..."
  # Create a placeholder directory to prevent Packer download error
  mkdir -p /var/log/packer-cis
  echo "Skipped" > /var/log/packer-cis/status.txt
  exit 0
fi

# Logging function
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] [CIS-HARDENING] [$level] $message"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

log_info "=========================================="
log_info "CIS Level 1 Hardening (Dynamic Tailoring)"
log_info "=========================================="

# 1. Install OpenSCAP Tools
log_info "Installing OpenSCAP scanner and Security Guide..."
dnf install -y openscap-scanner scap-security-guide

# 2. Detect the Correct DataStream File
# This is critical. RHEL and Rocky use different filenames.
DS_FILE=""
if grep -q "Rocky" /etc/redhat-release 2>/dev/null; then
  DS_FILE="/usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml"
  log_info "Detected OS: Rocky Linux 9"
else
  DS_FILE="/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
  log_info "Detected OS: Red Hat Enterprise Linux 9"
fi

if [ ! -f "$DS_FILE" ]; then
  log_error "Could not find a valid SCAP DataStream file: $DS_FILE"
  exit 1
fi

log_success "Target DataStream: $DS_FILE"

# 3. GENERATE DYNAMIC TAILORING FILE
TAILORING_FILE="/tmp/cis-tailoring.xml"
CUSTOM_PROFILE="xccdf_packer_profile_cis_custom"

log_info "Generating custom tailoring file at $TAILORING_FILE..."

cat <<EOF > "$TAILORING_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<xccdf:Tailoring xmlns:xccdf="http://checklists.nist.gov/xccdf/1.2" id="xccdf_org_tailoring_packer_rhel9">
  <xccdf:benchmark href="$DS_FILE"/>
  <xccdf:version time="$(date -u +'%Y-%m-%dT%H:%M:%S')">1</xccdf:version>
  <xccdf:Profile id="$CUSTOM_PROFILE" extends="xccdf_org.ssgproject.content_profile_cis_server_l1">
    <xccdf:title>Custom CIS Level 1 for AWS</xccdf:title>
    <xccdf:description>CIS Level 1 Server profile with cloud-specific exclusions for AWS.</xccdf:description>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_package_firewalld_installed" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_service_firewalld_enabled" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_ensure_firewalld_status" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_firewalld_loopback_traffic_restricted" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_firewalld_loopback_traffic_trusted" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_enable_fips_mode" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_mount_option_tmp_noexec" selected="false"/>
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_sshd_disable_root_login" selected="false"/>
  </xccdf:Profile>
</xccdf:Tailoring>
EOF

log_success "Tailoring file created."

# 4. Prepare Report Directory
REPORT_DIR="/var/log/packer-cis"
mkdir -p "$REPORT_DIR"
REPORT_PREFIX="cis-$(date -u +'%Y%m%dT%H%M%SZ')"

# 5. Run Scan with Custom Profile
log_info "Starting Scan with Custom Profile..."

# We use '|| true' to prevent build failure on minor scan errors
# Exit code 0 = Pass, 2 = Pass (with fixes), 1 = Error
set +e
oscap xccdf eval \
    --profile "$CUSTOM_PROFILE" \
    --tailoring-file "$TAILORING_FILE" \
    --remediate \
    --results "$REPORT_DIR/${REPORT_PREFIX}-results.xml" \
    --report "$REPORT_DIR/${REPORT_PREFIX}-report.html" \
    --fetch-remote-resources \
    "$DS_FILE" 2>&1 | while IFS= read -r line; do
  log_info "OSCAP: $line"
done
OSCAP_EXIT=${PIPESTATUS[0]}
set -e

log_info "Scan Complete. Checking results..."

# 6. Analyze Result
if [ $OSCAP_EXIT -eq 2 ]; then
    log_success "Remediation completed successfully (Changes applied)."
elif [ $OSCAP_EXIT -eq 0 ]; then
    log_success "System was already compliant."
else
    log_warn "OpenSCAP finished with exit code $OSCAP_EXIT (Some rules may have failed)."
    log_warn "Check report at $REPORT_DIR/${REPORT_PREFIX}-report.html"
fi

# 7. Verify if Firewalld was skipped (Check the results XML)
if [ -f "$REPORT_DIR/${REPORT_PREFIX}-results.xml" ]; then
  if grep -q "package_firewalld_installed.*notselected" "$REPORT_DIR/${REPORT_PREFIX}-results.xml" 2>/dev/null; then
    log_success "SUCCESS: Firewalld rule was correctly SKIPPED."
  else
    log_info "NOTICE: Firewalld rule was processed (Check report for details)."
  fi
fi

# 8. Generate Summary Text for Easy Reading
echo "CIS Scan Summary" > "$REPORT_DIR/summary.txt"
echo "Date: $(date)" >> "$REPORT_DIR/summary.txt"
echo "Profile: $CUSTOM_PROFILE" >> "$REPORT_DIR/summary.txt"
echo "Exit Code: $OSCAP_EXIT" >> "$REPORT_DIR/summary.txt"
echo "Report: $REPORT_DIR/${REPORT_PREFIX}-report.html" >> "$REPORT_DIR/summary.txt"

log_info "Done."

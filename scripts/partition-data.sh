#!/bin/bash
# CIS Compliance Partitioning Setup
# Creates separate mount points for /home, /var/tmp, /var/log, and /var/log/audit
# Works on both RHEL 9 and Rocky Linux 9

set -euo pipefail

# Logging function with timestamps and Packer-compatible format
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] [PARTITION-SETUP] [$level] $message"
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_error() {
  log "ERROR" "$@"
}

log_success() {
  log "SUCCESS" "$@"
}

log_info "=========================================="
log_info "CIS Partitioning Setup"
log_info "=========================================="
log_info "Start Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log_info ""

# Check if partitioning is enabled
if [[ "${ENABLE_PARTITIONING:-true}" != "true" ]]; then
  log_info "Partitioning is disabled. Skipping..."
  exit 0
fi

# 1. Install LVM and Rsync tools (NO SUDO - script runs as root)
log_info "Installing LVM2 and rsync..."
if dnf install -y lvm2 rsync; then
  log_success "LVM2 and rsync installed successfully"
else
  log_error "Failed to install LVM2 and rsync"
  exit 1
fi

# 2. Detect the New Disk
# Finds a disk that is NOT the root disk
log_info "Detecting disks..."
ROOT_DEVICE=$(findmnt / -o SOURCE -n 2>/dev/null || echo "")
ROOT_DISK=""

if [ -n "$ROOT_DEVICE" ]; then
  # Extract the disk name from the device (handles both /dev/xvda1 and /dev/nvme0n1p1)
  if [[ "$ROOT_DEVICE" == *"nvme"* ]]; then
    ROOT_DISK=$(echo "$ROOT_DEVICE" | sed 's/p[0-9]*$//' | sed 's|/dev/||')
  else
    ROOT_DISK=$(lsblk -no pkname "$ROOT_DEVICE" 2>/dev/null || echo "$ROOT_DEVICE" | sed 's/[0-9]*$//' | sed 's|/dev/||')
  fi
fi

if [ -z "$ROOT_DISK" ]; then
  # Fallback method
  ROOT_DISK=$(lsblk -dn -o NAME,TYPE | grep disk | head -1 | awk '{print $1}')
fi

log_info "Root disk: $ROOT_DISK"

# Find secondary disk (not the root disk)
# Try /dev/sdb first (traditional), then look for any other disk
if [ -b "/dev/sdb" ]; then
  NEW_DISK="/dev/sdb"
  log_info "Found secondary disk at /dev/sdb (traditional)"
elif lsblk -dn -o NAME,TYPE | grep -q "disk"; then
  # Find any disk that's not the root disk
  NEW_DISK=$(lsblk -dn -o NAME,TYPE | grep disk | grep -v "^$ROOT_DISK" | awk '{print "/dev/"$1}' | head -n 1)
  if [ -n "$NEW_DISK" ]; then
    log_info "Found secondary disk: $NEW_DISK"
  fi
fi

if [ -z "$NEW_DISK" ] || [ ! -b "$NEW_DISK" ]; then
  log_error "Secondary disk not found. Did you add launch_block_device_mappings for /dev/sdb?"
  log_error "Available disks:"
  lsblk -dn -o NAME,TYPE,SIZE
  exit 1
fi

log_success "Target disk found: $NEW_DISK"

# Wait a moment for disk to be fully available
sleep 2

# 3. Create LVM Structure (NO SUDO - script runs as root)
log_info "Initializing Physical Volume & Volume Group..."
if pvcreate "$NEW_DISK"; then
  log_success "Physical volume created"
else
  log_error "Failed to create physical volume"
  exit 1
fi

if vgcreate vg_data "$NEW_DISK"; then
  log_success "Volume group 'vg_data' created"
else
  log_error "Failed to create volume group"
  exit 1
fi

log_info "Creating Logical Volumes..."
# Check available space first
VG_FREE=$(vgs --noheadings -o vg_free --units g vg_data | sed 's/[^0-9.]//g' | awk '{print int($1)}')
log_info "Available space in volume group: ${VG_FREE}GB"

# Calculate conservative sizes based on available space
# For 50GB disk, after overhead: ~48GB usable
# Allocate: 8GB home, 4GB var/tmp, 15GB var/log, rest for audit
HOME_SIZE="8G"
TMP_SIZE="4G"
LOG_SIZE="15G"

# Adjust sizes if we have less space than expected
if [ "$VG_FREE" -lt 30 ]; then
  log_warn "Less space available than expected. Adjusting sizes..."
  HOME_SIZE="6G"
  TMP_SIZE="3G"
  LOG_SIZE="10G"
fi

if lvcreate -L "$HOME_SIZE" -n lv_home vg_data; then
  log_success "Logical volume 'lv_home' created ($HOME_SIZE)"
else
  log_error "Failed to create lv_home"
  exit 1
fi

if lvcreate -L "$TMP_SIZE" -n lv_var_tmp vg_data; then
  log_success "Logical volume 'lv_var_tmp' created ($TMP_SIZE)"
else
  log_error "Failed to create lv_var_tmp"
  exit 1
fi

if lvcreate -L "$LOG_SIZE" -n lv_var_log vg_data; then
  log_success "Logical volume 'lv_var_log' created ($LOG_SIZE)"
else
  log_error "Failed to create lv_var_log"
  exit 1
fi

# Get remaining space for audit
REMAINING=$(vgs --noheadings -o vg_free --units g vg_data | sed 's/[^0-9.]//g' | awk '{print int($1)}')
log_info "Remaining space for audit: ${REMAINING}GB"

if lvcreate -l 100%FREE -n lv_audit vg_data; then
  log_success "Logical volume 'lv_audit' created (remaining space ~${REMAINING}GB)"
else
  log_error "Failed to create lv_audit"
  exit 1
fi

log_info "Formatting Filesystems (XFS)..."
if mkfs.xfs -f /dev/vg_data/lv_home; then
  log_success "Formatted /dev/vg_data/lv_home"
else
  log_error "Failed to format lv_home"
  exit 1
fi

if mkfs.xfs -f /dev/vg_data/lv_var_tmp; then
  log_success "Formatted /dev/vg_data/lv_var_tmp"
else
  log_error "Failed to format lv_var_tmp"
  exit 1
fi

if mkfs.xfs -f /dev/vg_data/lv_var_log; then
  log_success "Formatted /dev/vg_data/lv_var_log"
else
  log_error "Failed to format lv_var_log"
  exit 1
fi

if mkfs.xfs -f /dev/vg_data/lv_audit; then
  log_success "Formatted /dev/vg_data/lv_audit"
else
  log_error "Failed to format lv_audit"
  exit 1
fi

# 4. Stop Services (Critical!) (NO SUDO - script runs as root)
# We must stop logging services to move /var/log safely
log_info "Stopping services for safe migration..."
systemctl stop rsyslog || log_warn "rsyslog not running or failed to stop"
# auditd often refuses to stop via systemctl, use service command or ignore
service auditd stop || log_warn "auditd not running or failed to stop (this is normal)"

# 5. Migration Helper Function (NO SUDO - script runs as root)
migrate_data() {
  local SRC=$1
  local DEST_DEV=$2
  local TEMP_MNT="/mnt/tmp_migrate"
  
  log_info "Migrating $SRC to $DEST_DEV..."
  
  if [ ! -d "$SRC" ]; then
    log_warn "Source directory $SRC does not exist, creating it"
    mkdir -p "$SRC"
  fi
  
  mkdir -p "$TEMP_MNT"
  
  if ! mount "$DEST_DEV" "$TEMP_MNT"; then
    log_error "Failed to mount $DEST_DEV"
    return 1
  fi
  
  # Sync data (preserve all permissions/SELinux labels)
  # 2>/dev/null suppresses error if source is empty
  if rsync -axHAX "$SRC/" "$TEMP_MNT/" 2>/dev/null; then
    log_success "Data migrated from $SRC"
  else
    log_warn "rsync completed with warnings (may be normal if directory is empty)"
  fi
  
  umount "$TEMP_MNT"
  rmdir "$TEMP_MNT" || true
}

# 6. Migrate Data (Order Matters!)
log_info "Migrating existing data to new partitions..."

migrate_data "/home" "/dev/vg_data/lv_home"
migrate_data "/var/tmp" "/dev/vg_data/lv_var_tmp"
migrate_data "/var/log" "/dev/vg_data/lv_var_log"
# Note: audit data is already inside /var/log, but we sync it specifically to the new audit vol
if [ -d "/var/log/audit" ]; then
  migrate_data "/var/log/audit" "/dev/vg_data/lv_audit"
else
  log_info "Creating /var/log/audit directory"
  mkdir -p /var/log/audit
fi

# 7. Configure fstab (Fail-Safe & Compliant) (NO SUDO - script runs as root)
log_info "Updating /etc/fstab..."
# 'nofail' ensures boot success even if disk is removed later.
# 'nodev,nosuid,noexec' are CIS requirements for these partitions.
tee -a /etc/fstab > /dev/null <<EOF

# CIS Compliance Partitions (added by Packer)
/dev/vg_data/lv_home      /home           xfs     defaults,nofail,nodev        0 0
/dev/vg_data/lv_var_tmp   /var/tmp        xfs     defaults,nofail,nodev,nosuid,noexec 0 0
/dev/vg_data/lv_var_log   /var/log        xfs     defaults,nofail,nodev,nosuid,noexec 0 0
/dev/vg_data/lv_audit     /var/log/audit  xfs     defaults,nofail,nodev,nosuid,noexec 0 0
EOF

log_success "fstab updated"

# 8. Mount and Restore (NO SUDO - script runs as root)
log_info "Mounting new partitions..."
# Mount all (order in fstab handles the nesting of /var/log and /var/log/audit)
if mount -a; then
  log_success "All partitions mounted successfully"
else
  log_error "Failed to mount partitions"
  exit 1
fi

log_info "Restoring SELinux Contexts..."
if restorecon -R /home /var/tmp /var/log 2>/dev/null; then
  log_success "SELinux contexts restored"
else
  log_warn "SELinux restorecon completed with warnings (may be normal)"
fi

log_info "Restarting Services..."
systemctl start rsyslog || log_warn "Failed to start rsyslog"
service auditd start || log_warn "Failed to start auditd (this is normal)"

log_info ""
log_info "=========================================="
log_success "Partitioning Complete"
log_info "=========================================="
log_info "Disk layout:"
lsblk
log_info ""
log_info "Mount points:"
df -h | grep -E "(home|var/tmp|var/log)"
log_info ""
log_info "End Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log_info "=========================================="

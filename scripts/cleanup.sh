#!/bin/bash
# Final cleanup and preparation script
# Works on both RHEL 9 and Rocky Linux 9

set -euo pipefail

# Check if cleanup is enabled
if [[ "${ENABLE_CLEANUP:-true}" != "true" ]]; then
  echo "Cleanup is disabled. Skipping..."
  exit 0
fi

# Detect OS for logging
if [ -f /etc/os-release ]; then
  source /etc/os-release
  echo "Starting final cleanup on $ID $VERSION_ID..."
else
  echo "Starting final cleanup..."
fi

# NO SUDO - script runs as root
# Clean cloud-init data
cloud-init clean

# Remove cloud-init logs
rm -f /var/log/cloud-init*.log

# Clean temporary directories
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear bash history
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# Clear system logs (optional - be careful in production)
journalctl --vacuum-time=1d || true

# Sync filesystem
sync

echo "Cleanup completed successfully."



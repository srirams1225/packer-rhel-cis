#!/bin/bash
# Configure root user and password
# Works on both RHEL 9 and Rocky Linux 9

set -euo pipefail

# Check if configure root is enabled
if [[ "${ENABLE_CONFIGURE_ROOT:-true}" != "true" ]]; then
  echo "Root configuration is disabled. Skipping..."
  exit 0
fi

# Detect OS for logging
if [ -f /etc/os-release ]; then
  source /etc/os-release
  echo "Configuring root user on $ID $VERSION_ID..."
else
  echo "Configuring root user..."
fi

# Set root password (works on both RHEL & Rocky)
# Check if ROOT_PASSWORD is set
if [[ -z "${ROOT_PASSWORD:-}" ]]; then
  echo "ERROR: ROOT_PASSWORD environment variable is not set"
  exit 1
fi

# NO SUDO - script runs as root
echo "root:${ROOT_PASSWORD}" | chpasswd

# Unlock root account (CRITICAL for RHEL 9 - root is locked by default)
passwd -u root

# Enable root SSH login (only if ENABLE_ROOT_SSH_LOGIN is set to "true")
if [[ "${ENABLE_ROOT_SSH_LOGIN:-false}" == "true" ]]; then
  echo "Enabling root SSH login (as requested)..."
  sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

  # Restart SSH service
  if systemctl is-active --quiet sshd; then
    systemctl restart sshd
  elif systemctl is-active --quiet ssh; then
    systemctl restart ssh
  fi
  echo "Root SSH login enabled."
else
  echo "Root SSH login is DISABLED (compliance best practice)."
  echo "Root password is set, but SSH login as root is not allowed."
  echo "Use a non-root user with sudo privileges instead."
fi

echo "Root user configuration completed successfully."



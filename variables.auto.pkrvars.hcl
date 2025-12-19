# Default variable values (not secrets!)
# This file is auto-loaded by Packer due to the .auto.pkrvars.hcl naming convention
# Override these with -var flags or environment variables

aws_region      = "us-east-1"
instance_type   = "c6i.2xlarge"
ami_name_prefix = "rhel9-base"
linux_variant   = "rhel" # Options: "rhel" or "rocky"

# SSH Configuration
# Note: SSH requires public IP or VPN/bastion access
# associate_public_ip_address = true  # Required for SSH (default: true)

# IAM Configuration (optional)
# iam_instance_profile = ""  # IAM instance profile name (optional)

# VPC Configuration (optional)
# subnet_id                   = ""  # VPC subnet ID
# vpc_id                      = ""  # VPC ID
# associate_public_ip_address = true  # Set to true for SSH access (default: true)

# Root Volume Configuration
root_volume_size      = 30    # Root volume size in GB
root_volume_type      = "gp3" # Volume type: gp3 (recommended), gp2, io1, etc.
root_volume_encrypted = true  # Enable encryption for root volume (recommended for compliance)

# Provisioner Control Flags (enable/disable individual steps)
enable_partitioning      = true  # Enable partitioning setup (creates separate mount points)
enable_system_update     = true  # Enable system update and patch
enable_configure_root     = true  # Enable root user configuration (sets password, unlocks account)
enable_upload_tailoring  = true  # Enable upload of CIS tailoring file
enable_cis_hardening     = true  # Enable CIS Level 1 hardening (applies OpenSCAP remediation)
enable_download_reports  = true  # Enable download of CIS compliance reports
enable_cleanup           = true  # Enable final cleanup

# Security Configuration
enable_root_ssh_login    = false # Enable root SSH login (NOT recommended for production/compliance)
                                # Default: false - Root password is set but SSH login is disabled
                                # Set to true only if you need root SSH access (not recommended)

# Data Disk Configuration (for CIS compliance partitions)
data_disk_size      = 50    # Size of additional data disk in GB (for /home, /var/tmp, /var/log, /var/log/audit)
data_disk_type      = "gp3" # Volume type: gp3 (recommended), gp2, io1, etc.
data_disk_encrypted = true  # Enable encryption for the data disk (recommended for compliance)

# root_password should be set via:
# - packer build -var 'root_password=YourPassword' main.pkr.hcl
# - or PKR_VAR_root_password environment variable
# DO NOT put the actual password here!


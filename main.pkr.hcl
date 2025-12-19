# Main Packer entry point

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

# Determine which source to use based on linux_variant variable
locals {
  source_name = var.linux_variant == "rhel" ? "source.amazon-ebs.rhel9" : "source.amazon-ebs.rocky9"
  os_name     = var.linux_variant == "rhel" ? "RHEL 9" : "Rocky Linux 9"
}

build {
  name    = "${var.linux_variant}9-ami-ssm-build"
  sources = [ local.source_name ]

  # ... (ssm-stabilize is fine as is) ...

  # 1. Partitioning Setup (MUST BE EARLY - before system updates)
  # Creates separate mount points for CIS compliance: /home, /var/tmp, /var/log, /var/log/audit
  provisioner "shell" {
    name             = "partition-setup"
    environment_vars = [ "ENABLE_PARTITIONING=${var.enable_partitioning}" ]
    script           = "${path.root}/scripts/partition-data.sh"
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }

  # 2. System Update (Needs Root)
  # Now updates will go into the NEW partitions
  provisioner "shell" {
    name             = "system-update"
    environment_vars = [ "ENABLE_SYSTEM_UPDATE=${var.enable_system_update}" ]
    script           = "${path.root}/scripts/system-update.sh"
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }

  # 3. Configure Root (Needs Root)
  # Configure root before CIS hardening (needed for build process)
  # Note: Root SSH login is controlled by enable_root_ssh_login variable (default: false for compliance)
  provisioner "shell" {
    name             = "configure-root"
    environment_vars = [
      "ROOT_PASSWORD=${var.root_password}",
      "ENABLE_ROOT_SSH_LOGIN=${var.enable_root_ssh_login}",
      "ENABLE_CONFIGURE_ROOT=${var.enable_configure_root}"
    ]
    script           = "${path.root}/scripts/configure-root.sh"
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    # This ensures variables are properly escaped and passed through sudo
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }

  # 4. CIS Hardening (Needs Root) - Runs at the end, after root is configured
  # Note: Tailoring file is now generated dynamically by the script (no upload needed)
  # CIS may disable root login, but cleanup will still work via sudo
  provisioner "shell" {
    name             = "cis-hardening"
    environment_vars = [ "ENABLE_CIS_HARDENING=${var.enable_cis_hardening}" ]
    script           = "${path.root}/scripts/cis-hardening.sh"
    timeout          = "20m"
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    # This ensures variables are properly escaped and passed through sudo
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }

  # Download CIS Reports (optional - downloads compliance reports for auditing)
  # Create tarball if reports exist, then download it
  provisioner "shell" {
    name             = "prepare-cis-reports"
    environment_vars = [
      "ENABLE_DOWNLOAD_REPORTS=${var.enable_download_reports}",
      "ENABLE_CIS_HARDENING=${var.enable_cis_hardening}"
    ]
    inline = [
      "if [[ \"${var.enable_download_reports}\" == \"true\" && \"${var.enable_cis_hardening}\" == \"true\" && -d \"/var/log/packer-cis\" ]]; then",
      "  echo 'Preparing CIS reports for download...'",
      "  cd /var/log/packer-cis && tar -czf /tmp/cis-reports.tar.gz . 2>/dev/null || echo 'No reports to archive'",
      "  echo 'CIS reports archived to /tmp/cis-reports.tar.gz'",
      "else",
      "  echo 'CIS report download skipped (CIS hardening disabled or reports not found)'",
      "  touch /tmp/cis-reports.tar.gz  # Create empty file so download doesn't fail",
      "fi"
    ]
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }

  # Download the tarball (will be empty if CIS was disabled, but won't fail)
  provisioner "file" {
    direction   = "download"
    source      = "/tmp/cis-reports.tar.gz"
    destination = "./cis-reports.tar.gz"
  }

  # 5. Cleanup (Needs Root) - Final step at the end
  provisioner "shell" {
    name             = "finalize"
    environment_vars = [ "ENABLE_CLEANUP=${var.enable_cleanup}" ]
    script           = "${path.root}/scripts/cleanup.sh"
    # Use 'env {{ .Vars }}' to safely pass all environment variables
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} sh -c '{{ .Path }}'"
  }
}


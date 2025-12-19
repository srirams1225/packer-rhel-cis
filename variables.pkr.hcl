# Variable declarations
# Default values are in pkrvars.hcl

variable "aws_region" {
  type        = string
  description = "AWS region to build the AMI in"
}

variable "root_password" {
  type        = string
  description = "Root user password"
  sensitive   = true
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for building"
}

variable "ami_name_prefix" {
  type        = string
  description = "Prefix for the AMI name"
}

variable "linux_variant" {
  type        = string
  description = "Linux variant to build: 'rhel' or 'rocky'"
  validation {
    condition     = contains(["rhel", "rocky"], var.linux_variant)
    error_message = "Linux_variant must be either 'rhel' or 'rocky'."
  }
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile name (optional, for additional permissions)"
  default     = ""
}

variable "subnet_id" {
  type        = string
  description = "VPC subnet ID (optional, for private subnets with VPC endpoints)"
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "VPC ID (optional, for private subnets)"
  default     = ""
}

variable "associate_public_ip_address" {
  type        = bool
  description = "Associate public IP address (required for SSH, set to true for public subnets)"
  default     = true
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GB"
  default     = 30
}

variable "root_volume_type" {
  type        = string
  description = "Root volume type (gp3, gp2, io1, etc.)"
  default     = "gp3"
}

variable "root_volume_encrypted" {
  type        = bool
  description = "Enable encryption for root volume"
  default     = true
}

variable "enable_cis_hardening" {
  type        = bool
  description = "Enable CIS Level 1 hardening (applies OpenSCAP remediation)"
  default     = true
}

variable "enable_partitioning" {
  type        = bool
  description = "Enable partitioning setup (creates separate mount points for CIS compliance)"
  default     = true
}

variable "enable_system_update" {
  type        = bool
  description = "Enable system update and patch"
  default     = true
}

variable "enable_configure_root" {
  type        = bool
  description = "Enable root user configuration (password, SSH login)"
  default     = true
}

variable "enable_upload_tailoring" {
  type        = bool
  description = "Enable upload of CIS tailoring file (only used if CIS hardening is enabled)"
  default     = true
}

variable "enable_download_reports" {
  type        = bool
  description = "Enable download of CIS compliance reports"
  default     = true
}

variable "enable_cleanup" {
  type        = bool
  description = "Enable final cleanup (removes temporary files, logs, etc.)"
  default     = true
}

variable "enable_root_ssh_login" {
  type        = bool
  description = "Enable root SSH login (NOT recommended for production/compliance - use non-root user instead)"
  default     = false
}

variable "data_disk_size" {
  type        = number
  description = "Size of the additional data disk for compliance partitions (GB)"
  default     = 50
}

variable "data_disk_type" {
  type        = string
  description = "Volume type for the data disk (gp3, gp2, io1, etc.)"
  default     = "gp3"
}

variable "data_disk_encrypted" {
  type        = bool
  description = "Enable encryption for the data disk"
  default     = true
}



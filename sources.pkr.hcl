# Builder source definitions

# Rocky Linux 9 AMI Source
source "amazon-ebs" "rocky9" {
  ami_name      = "${var.ami_name_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  instance_type = var.instance_type
  region        = var.aws_region

  # Rocky Linux 9 AMI (x86_64)
  # Owner ID: 792107900819 (Rocky Linux)
  # Find latest: aws ec2 describe-images --owners 792107900819 --filters "Name=name,Values=Rocky-9-EC2-Base-*" "Name=architecture,Values=x86_64" --query 'Images | sort_by(@, &CreationDate) | [-1]'
  source_ami_filter {
    filters = {
      name                = "Rocky-9-EC2-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    most_recent = true
    owners      = ["792107900819"]
  }

  # SSH configuration
  ssh_username = "rocky"
  ssh_timeout  = "10m"

  # Explicit root volume mapping (predictable disk size, easier compliance)
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    delete_on_termination = true
    encrypted             = var.root_volume_encrypted
  }

  # Compliance Data Disk (for /home, /var/tmp, /var/log, /var/log/audit)
  # This disk will be partitioned into separate mount points for CIS compliance
  launch_block_device_mappings {
    device_name           = "/dev/sdb"
    volume_size           = var.data_disk_size
    volume_type           = var.data_disk_type
    delete_on_termination = true
    encrypted             = var.data_disk_encrypted
  }

  # VPC configuration (optional)
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  vpc_id                       = var.vpc_id != "" ? var.vpc_id : null
  associate_public_ip_address = var.associate_public_ip_address

  # Security group (optional - can be added if needed)
  # security_group_ids = []

  tags = {
    Name      = "${var.ami_name_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
    OS        = "Rocky Linux 9"
    CreatedBy = "Packer"
    BuildDate = formatdate("YYYY-MM-DD", timestamp())
  }
}

# RHEL 9 AMI Source
source "amazon-ebs" "rhel9" {
  ami_name      = "${var.ami_name_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  instance_type = var.instance_type
  region        = var.aws_region

  # RHEL 9 AMI (x86_64)
  # Owner ID: 309956199498 (AWS Marketplace RHEL)
  source_ami_filter {
    filters = {
      name                = "RHEL-9.*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    most_recent = true
    owners      = ["309956199498"]
  }

  # SSH configuration
  ssh_username = "ec2-user"
  ssh_timeout  = "10m"

  # Explicit root volume mapping (predictable disk size, easier compliance)
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    delete_on_termination = true
    encrypted             = var.root_volume_encrypted
  }

  # Compliance Data Disk (for /home, /var/tmp, /var/log, /var/log/audit)
  # This disk will be partitioned into separate mount points for CIS compliance
  launch_block_device_mappings {
    device_name           = "/dev/sdb"
    volume_size           = var.data_disk_size
    volume_type           = var.data_disk_type
    delete_on_termination = true
    encrypted             = var.data_disk_encrypted
  }

  # VPC configuration (optional)
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  vpc_id                       = var.vpc_id != "" ? var.vpc_id : null
  associate_public_ip_address = var.associate_public_ip_address

  # Security group (optional - can be added if needed)
  # security_group_ids = []

  tags = {
    Name      = "${var.ami_name_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
    OS        = "RHEL 9"
    CreatedBy = "Packer"
    BuildDate = formatdate("YYYY-MM-DD", timestamp())
  }
}



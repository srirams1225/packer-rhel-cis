#!/bin/bash
set -e  # Exit immediately if any command fails

# Check if system update is enabled
if [[ "${ENABLE_SYSTEM_UPDATE:-true}" != "true" ]]; then
  echo "System update is disabled. Skipping..."
  exit 0
fi

echo ">>> OPTIMIZING DNF PERFORMANCE <<<"

# 1. Force IPv4 (Fixes generic IPv6 timeouts on AWS)
# AWS repositories sometimes have IPv6 connectivity issues
echo "ip_resolve=4" >> /etc/dnf/dnf.conf
echo "Configured DNF to use IPv4 only"

# 2. Enable Parallel Downloads (The big speed boost)
# Default is 3. We bump it to 10 for faster downloads
# This allows downloading 10 packages simultaneously instead of one at a time
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
echo "Configured DNF for parallel downloads (10 simultaneous)"

# 3. Enable Fastest Mirror
# Automatically selects the fastest mirror from available repositories
echo "fastestmirror=True" >> /etc/dnf/dnf.conf
echo "Enabled fastest mirror selection"

# 4. Wait for cloud-init to finish
# cloud-init may be running updates in the background, causing dnf lock conflicts
echo "Waiting for cloud-init to finish boot tasks..."
if command -v cloud-init >/dev/null 2>&1; then
  /usr/bin/cloud-init status --wait || echo "cloud-init status check completed (may have already finished)"
else
  echo "cloud-init not found, skipping wait"
fi

# 5. Clear metadata to force a fresh, fast resolution
echo "Clearing DNF metadata cache..."
dnf clean all

echo ">>> STARTING DISK RESIZE AND SYSTEM UPDATE <<<"

# 1. Install required tools
# 'cloud-utils-growpart' contains the growpart command needed for AWS EBS resizing
echo "Installing resize tools..."
dnf install -y cloud-utils-growpart gdisk

# 2. Dynamically Identify Devices
# finding where '/' is mounted (e.g., /dev/nvme0n1p4 or /dev/mapper/root)
ROOT_MOUNT=$(findmnt / -o SOURCE -n)
echo "Detected Root Mount: $ROOT_MOUNT"

# If root is LVM (common in RHEL), we need to find the underlying physical device
if [[ "$ROOT_MOUNT" == *"/mapper/"* ]]; then
    echo "LVM detected."
    # Get the physical device backing the LVM (e.g., nvme0n1p4)
    # We use pvs to find the device associated with the root volume group
    PHYSICAL_PART=$(pvs --noheadings -o pv_name | tr -d ' ' | head -n 1)
else
    echo "Standard Partition detected."
    PHYSICAL_PART=$ROOT_MOUNT
fi

echo "Target Physical Partition: $PHYSICAL_PART"

# Get the Parent Disk (e.g., /dev/nvme0n1) from the partition
PARENT_DISK="/dev/$(lsblk -no pkname "$PHYSICAL_PART")"
echo "Parent Disk: $PARENT_DISK"

# Get the Partition Number (e.g., 4)
PART_NUM=$(echo "$PHYSICAL_PART" | grep -oE '[0-9]+$')
echo "Partition Number: $PART_NUM"

# 3. Perform Resize
echo ">>> Extending Partition Table..."
# growpart expands the partition to fill the EBS volume
growpart "$PARENT_DISK" "$PART_NUM" || echo "Partition likely already max size. Continuing..."

# 4. Resize Filesystem
if [[ "$ROOT_MOUNT" == *"/mapper/"* ]]; then
    echo ">>> Resizing LVM..."
    # 1. Resize the Physical Volume (PV) to match the new partition size
    pvresize "$PHYSICAL_PART"
    
    # 2. Extend the Logical Volume (LV) to use 100% of the new space
    # -r automatically resizes the filesystem (xfs/ext4) underneath
    lvextend -l +100%FREE -r "$ROOT_MOUNT"
else
    echo ">>> Resizing XFS..."
    # For standard partitions, just grow the file system
    xfs_growfs /
fi

echo ">>> DISK RESIZE COMPLETE. New Layout:"
lsblk
df -h /

# 5. Run System Updates
echo ">>> STARTING DNF UPDATE..."
dnf update -y
echo ">>> SYSTEM UPDATE COMPLETE <<<"
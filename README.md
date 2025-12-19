# Hardened RHEL 9 & Rocky Linux 9 AMI Builds with Packer (CIS Level 1)

## TL;DR

* Builds **hardened RHEL 9 and Rocky Linux 9 AMIs** on AWS
* **CIS Level 1** compliance using **OpenSCAP** with dynamic tailoring
* **LVM-based partitioning** aligned with CIS recommendations
* Uses **SSH communicator** (explicit design choice)
* CI/CD ready: GitHub Actions, GitLab CI, AWS CodeBuild
* Includes cleanup automation for stale AMIs and snapshots

---

## Overview

This project provides a **production-grade Packer setup** to build hardened Amazon Machine Images (AMIs) for **RHEL 9** and **Rocky Linux 9**. The images are hardened to **CIS Level 1** benchmarks using **OpenSCAP**, with dynamic tailoring to accommodate cloud-specific requirements.

The goal is to produce **secure, repeatable, and auditable AMIs** suitable for enterprise and regulated environments.

---

## Key Design Principles

### 1. SSH Communicator (Intentional Choice)

This project **intentionally uses the SSH communicator**:

* Keeps builds simple and reproducible
* Works in standard public subnets without additional AWS infrastructure
* Aligns with common enterprise Packer usage

> A minimal SSM policy is included **for reference only** for teams that may want to migrate to `communicator = "ssm"` in the future.

---

### 2. CIS Level 1 with Dynamic Tailoring

* Uses **OpenSCAP** for compliance scanning
* Dynamically generates tailoring files at build time
* Excludes controls that are:

  * Cloud-incompatible
  * Handled by AWS (e.g., security groups)
  * Known to cause false positives in EC2 environments

  OpenSCAP exit codes are handled safely:

* Exit code `2` (non-compliant findings) **does not fail the build**
* Build only fails on execution or configuration errors

* Customizing CIS Hardening (Skipping Rules)

  This pipeline dynamically generates the CIS Tailoring file during the build to support both RHEL 9 and Rocky Linux 9. 

**To disable specific CIS rules that conflict with your application, follow these steps:**

##### A. Identify the Rule ID
You cannot use the rule name; you must use the **OpenSCAP Rule ID**.
1. Run a build and download the artifact `cis-reports.tar.gz`.
2. Open the HTML report in your browser.
3. Find the failed rule and click the title to expand it.
4. Copy the **Rule ID** (e.g., `xccdf_org.ssgproject.content_rule_package_aide_installed`).

##### B. Update the Hardening Script
1. Open `scripts/cis-hardening.sh`.
2. Scroll to the **"GENERATE DYNAMIC TAILORING FILE"** section (Step 3).
3. Add a new `<xccdf:select>` line inside the `cat <<EOF` block.

**Example:**
```bash
# ... inside scripts/cis-hardening.sh ...

cat <<EOF > "$TAILORING_FILE"
# ... (headers) ...
  <xccdf:Profile id="$CUSTOM_PROFILE" extends="xccdf_org.ssgproject.content_profile_cis_server_l1">
    
    <xccdf:select idref="xccdf_org.ssgproject.content_rule_package_firewalld_installed" selected="false"/>

    <xccdf:select idref="xccdf_org.ssgproject.content_rule_package_aide_installed" selected="false"/>

  </xccdf:Profile>
</xccdf:Tailoring>
EOF
```
---

### 3. CIS-Aligned Disk Layout (LVM)

The AMI includes CIS-recommended partitioning using LVM:

* `/var`
* `/var/log`
* `/var/log/audit`
* `/home`
* `/tmp`

Disk detection logic dynamically identifies the **non-root EBS volume**, ensuring correctness across instance types.

---

### 4. Security-Conscious Defaults

* Root SSH login disabled
* Password-based authentication controlled explicitly
* SELinux enabled
* Firewalld exclusions documented (AWS SGs operate at L3/L4)

⚠️ **Security Note**

A root password is set during the AMI build **only** to support CIS hardening steps.

In production environments, this should be replaced with:

* AWS SSM Session Manager
* Secrets Manager
* cloud-init one-time credentials

This tradeoff is intentional and documented.

---

## Repository Structure

```
.
├── main.pkr.hcl                 # Packer build definition
├── sources.pkr.hcl              # RHEL 9 and Rocky 9 sources
├── variables.pkr.hcl            # Variable definitions
├── pkrvars.hcl                  # Default variable values
│
├── scripts/
│   ├── disk-setup.sh            # LVM & filesystem configuration
│   ├── cis-hardening.sh         # OpenSCAP CIS hardening
│   ├── cis-tailoring.sh         # Dynamic tailoring generation
│   ├── cleanup.sh               # Build cleanup logic
│   └── common.sh                # Shared helpers
│
├── iam/
│   └── ssm-minimal-instance-policy.json  # Reference-only (not used)
│
├── ci/
│   ├── github-actions.yml
│   ├── gitlab-ci.yml
│   └── codebuild.yml
│
└── tools/
    └── cleanup-old-amis.sh      # AMI & snapshot cleanup utility
```

---

## Prerequisites

* Packer >= 1.8
* AWS CLI configured
* IAM permissions to:

  * Launch EC2 instances
  * Create and register AMIs
  * Create and delete EBS volumes and snapshots

### Required Network Access

* SSH (port 22) from Packer host to build instance
* Outbound internet access for package installation

---

## Usage

### Validate Template

```bash
packer init .
packer validate -var-file=pkrvars.hcl .
```

### Build AMI

```bash
packer build \
  -var-file=pkrvars.hcl \
  -var-file=my-build.pkrvars.hcl \
  -var 'root_password=REPLACE_ME' \
  .
```

---

## CI/CD Support

This project includes examples for:

* GitHub Actions
* GitLab CI
* AWS CodeBuild

Each pipeline:

* Runs `packer init`
* Validates templates
* Builds AMIs in a controlled environment

---

## AMI Cleanup

A utility script is provided to:

* Deregister old AMIs
* Delete associated snapshots
* Retain the latest N images per OS

This prevents long-term snapshot cost accumulation.

---

## Known Limitations

* Designed for **AWS EC2 only**
* CIS Level 1 (Level 2 intentionally excluded)
* SSH-based builds require reachable network paths

---

## Future Enhancements

* Optional SSM communicator support
* Secrets Manager integration
* CIS Level 2 profiles
* GovCloud-compatible variants

---

## License

MIT

---

## Author Notes

This repository is intentionally designed to reflect **real-world enterprise tradeoffs**, not theoretical best-case scenarios. Every decision (SSH vs SSM, CIS tailoring, soft-fail scans) is documented.

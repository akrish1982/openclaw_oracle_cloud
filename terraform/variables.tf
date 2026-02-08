# =============================================================================
# OCI Authentication
# =============================================================================
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "API Key fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key PEM file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region (e.g., us-ashburn-1, us-phoenix-1, eu-frankfurt-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment OCID (use tenancy_ocid for root compartment)"
  type        = string
}

variable "availability_domain_index" {
  description = "Index of the availability domain to use (0, 1, or 2). Change this if one AD is out of capacity."
  type        = number
  default     = 0
}

# =============================================================================
# Instance Configuration
# =============================================================================
variable "instance_display_name" {
  description = "Display name for the compute instance"
  type        = string
  default     = "openclaw-server"
}

variable "instance_shape" {
  description = "Compute shape (VM.Standard.A1.Flex = free ARM)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs (max 4 on free tier for A1.Flex)"
  type        = number
  default     = 4
}

variable "instance_memory_gb" {
  description = "Memory in GB (max 24 on free tier for A1.Flex)"
  type        = number
  default     = 24
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB (47-200 on free tier, total 200 across instances)"
  type        = number
  default     = 100
}

variable "ubuntu_image_ocid" {
  description = "OCID for Ubuntu 22.04 Minimal aarch64 image in your region. Find via: oci compute image list --compartment-id <TENANCY> --operating-system 'Canonical Ubuntu' --operating-system-version '22.04 Minimal aarch64' --shape VM.Standard.A1.Flex --limit 1"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for instance access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key (for provisioner connections)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# =============================================================================
# Networking
# =============================================================================
variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# =============================================================================
# OpenClaw / API Configuration
# =============================================================================
variable "anthropic_api_key" {
  description = "Anthropic API key for Claude (leave empty to use setup-token later)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openrouter_api_key" {
  description = "OpenRouter API key for Kimi K2.5 (get from https://openrouter.ai/keys)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "telegram_bot_token" {
  description = "Telegram bot token from @BotFather"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ollama_model" {
  description = "Default Ollama model to pull (ARM64-friendly)"
  type        = string
  default     = "qwen2.5-coder:14b"
}

# =============================================================================
# Tailscale
# =============================================================================
variable "tailscale_auth_key" {
  description = "Tailscale auth key for unattended setup (generate at https://login.tailscale.com/admin/settings/keys)"
  type        = string
  default     = ""
  sensitive   = true
}

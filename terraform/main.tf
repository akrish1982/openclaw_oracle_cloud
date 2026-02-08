# =============================================================================
# OpenClaw on Oracle Cloud Infrastructure (OCI) Free Tier
# Deploys: VCN + Subnet + Security List + ARM Instance + Cloud-Init
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# =============================================================================
# Provider
# =============================================================================
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = pathexpand(var.private_key_path)
  region           = var.region
}

# =============================================================================
# Data Sources
# =============================================================================
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# =============================================================================
# Networking: VCN
# =============================================================================
resource "oci_core_vcn" "openclaw_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "openclaw-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "openclawvcn"

  freeform_tags = {
    project = "openclaw"
  }
}

# =============================================================================
# Networking: Internet Gateway
# =============================================================================
resource "oci_core_internet_gateway" "openclaw_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openclaw_vcn.id
  display_name   = "openclaw-igw"
  enabled        = true
}

# =============================================================================
# Networking: Route Table
# =============================================================================
resource "oci_core_route_table" "openclaw_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openclaw_vcn.id
  display_name   = "openclaw-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.openclaw_igw.id
  }
}

# =============================================================================
# Networking: Security List
# =============================================================================
resource "oci_core_security_list" "openclaw_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openclaw_vcn.id
  display_name   = "openclaw-security-list"

  # --- Egress: Allow all outbound ---
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  # --- Ingress: SSH (port 22) ---
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # --- Ingress: ICMP (ping) ---
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol  = "1"
    source    = var.vcn_cidr
    stateless = false
    icmp_options {
      type = 3
    }
  }

  # --- Ingress: OpenClaw Gateway (port 18789) - restrict to VCN only ---
  # OpenClaw gateway doesn't need public access; Telegram uses outbound webhooks
  # Uncomment below if you want remote access to the dashboard
  # ingress_security_rules {
  #   protocol  = "6"
  #   source    = "YOUR_HOME_IP/32"
  #   stateless = false
  #   tcp_options {
  #     min = 18789
  #     max = 18789
  #   }
  # }
}

# =============================================================================
# Networking: Public Subnet
# =============================================================================
resource "oci_core_subnet" "openclaw_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.openclaw_vcn.id
  display_name               = "openclaw-public-subnet"
  cidr_block                 = var.subnet_cidr
  dns_label                  = "openclawsub"
  route_table_id             = oci_core_route_table.openclaw_rt.id
  security_list_ids          = [oci_core_security_list.openclaw_sl.id]
  prohibit_public_ip_on_vnic = false
}

# =============================================================================
# Compute: ARM Instance (Always Free A1.Flex)
# =============================================================================
resource "oci_core_instance" "openclaw_instance" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = var.instance_display_name
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = var.ubuntu_image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.openclaw_subnet.id
    display_name     = "openclaw-vnic"
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      anthropic_api_key  = var.anthropic_api_key
      openrouter_api_key = var.openrouter_api_key
      telegram_bot_token = var.telegram_bot_token
      ollama_model       = var.ollama_model
      tailscale_auth_key = var.tailscale_auth_key
    }))
  }

  freeform_tags = {
    project = "openclaw"
  }

  # Prevent accidental destruction
  lifecycle {
    prevent_destroy = false
  }
}

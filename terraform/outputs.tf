output "instance_public_ip" {
  description = "Public IP of the OpenClaw instance"
  value       = oci_core_instance.openclaw_instance.public_ip
}

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.openclaw_instance.id
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.openclaw_vcn.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${oci_core_instance.openclaw_instance.public_ip}"
}

output "setup_instructions" {
  description = "Post-deploy instructions"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║  OpenClaw Instance Deployed!                                    ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  1. SSH into the instance:                                       ║
    ║     ssh -i ${var.ssh_private_key_path} ubuntu@${oci_core_instance.openclaw_instance.public_ip}
    ║                                                                  ║
    ║  2. Wait ~5 min for cloud-init to finish, then check:           ║
    ║     cloud-init status --wait                                     ║
    ║                                                                  ║
    ║  3. Run OpenClaw setup:                                          ║
    ║     sudo bash /home/ubuntu/setup-openclaw.sh                     ║
    ║                                                                  ║
    ║  4. Configure and pair Telegram:                                 ║
    ║     sudo su - openclaw                                           ║
    ║     openclaw onboard                                             ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
  EOT
}

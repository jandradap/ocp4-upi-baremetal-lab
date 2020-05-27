locals {
  ocp_master = [
    for master_index in range(var.ocp_cluster.num_masters) :
      {
        hostname = format("master%02d", master_index)
        fqdn     = format("master%02d.%s", master_index, var.dns.domain)
        ip       = lookup(var.ocp_inventory, format("master%02d", master_index)).ip_address
        mac      = lookup(var.ocp_inventory, format("master%02d", master_index)).mac_address
      }
  ]
}

resource "libvirt_ignition" "ocp_master" {

  count = var.ocp_cluster.num_masters

  name    = format("%s.ign", element(local.ocp_master, count.index).hostname)
  pool    = libvirt_pool.openshift.name
  content = data.local_file.ocp_ignition_master.content
}

resource "libvirt_volume" "ocp_master_image" {

  count = var.ocp_cluster.num_masters

  name   = format("%s-baseimg.qcow2", element(local.ocp_master, count.index).hostname)
  pool   = libvirt_pool.openshift.name
  source = var.ocp_master.base_img
  format = "qcow2"
}

resource "libvirt_volume" "ocp_master" {

  count = var.ocp_cluster.num_masters

  name           = format("%s-volume.qcow2", element(local.ocp_master, count.index).hostname)
  pool           = libvirt_pool.openshift.name
  base_volume_id = element(libvirt_volume.ocp_master_image.*.id, count.index)
  format         = "qcow2"
}

resource "libvirt_domain" "ocp_master" {

  count = var.ocp_cluster.num_masters

  name    = format("ocp-%s", element(local.ocp_master, count.index).hostname)
  memory  = var.ocp_master.memory
  vcpu    = var.ocp_master.vcpu
  running = false

  coreos_ignition = element(libvirt_ignition.ocp_master.*.id, count.index)

  disk {
    volume_id = element(libvirt_volume.ocp_master.*.id, count.index)
    scsi      = false
  }

  network_interface {
    network_name   = libvirt_network.openshift.name
    hostname       = element(local.ocp_master, count.index).fqdn
    addresses      = [ element(local.ocp_master, count.index).ip ]
    mac            = element(local.ocp_master, count.index).mac
    wait_for_lease = true
  }

  console {
    type           = "pty"
    target_type    = "serial"
    target_port    = "0"
    source_host    = "127.0.0.1"
    source_service = "0"
  }

  graphics {
    type           = "spice"
    listen_type    = "address"
    listen_address = "127.0.0.1"
    autoport       = true
  }

  provisioner "local-exec" {
    when    = destroy
    command = format("ssh-keygen -R %s || true", self.network_interface.0.hostname)
  }
}
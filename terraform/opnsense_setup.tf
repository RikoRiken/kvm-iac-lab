# =================================================================
#           OPNsense AUTOMATISATION  (Image + Config)
# =================================================================

# --- PART 1 : DOWNLOAD BASE ISO IMAGE ---

resource "null_resource" "download_opnsense" {
  triggers = {
    check_file = fileexists("${path.module}/opnsense-nano.qcow2") ? "exists" : timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      if [ -f "${path.module}/opnsense-nano.qcow2" ]; then
        exit 0
      fi
      echo "⬇️ Downloading OPNsense raw image..."
      wget -q -O opnsense.img.bz2 https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.7/OPNsense-24.7-nano-amd64.img.bz2
      
      echo "📦 Unzipping & converting image to '.qcow2'..."
      bzip2 -d opnsense.img.bz2
      qemu-img convert -f raw -O qcow2 opnsense.img opnsense-nano.qcow2
      
      rm -f opnsense.img
    EOT
  }
}

resource "libvirt_volume" "fw_disk" {
  name       = "opnsense-fw.qcow2"
  pool       = "default"
  format     = "qcow2"
  source     = "${path.module}/opnsense-nano.qcow2"
  depends_on = [null_resource.download_opnsense]
}


# --- PART 2 : INJECT CONFIG FILE (XML) ---

# Creating local XML file
resource "local_file" "opnsense_config_xml" {
  filename = "${path.module}/opnsense_data/conf/config.xml"
  content  = <<EOT
<?xml version="1.0"?>
<opnsense>
  <trigger_initial_wizard>false</trigger_initial_wizard>
  <theme>opnsense</theme>
  <system>
    <hostname>vm-fw</hostname>
    <domain>${var.domain_name}</domain> 
    <ssh>
      <enabled>enabled</enabled>
      <permitrootlogin>1</permitrootlogin>
      <password>opnsense</password>
      <port>22</port>
    </ssh>
  </system>
  <interfaces>
    <wan>
      <if>vtnet0</if>
      <enable>1</enable>
      <ipaddr>dhcp</ipaddr>
    </wan>
    <lan>
      <if>vtnet1</if>
      <enable>1</enable>
      <ipaddr>192.168.10.1</ipaddr>
      <subnet>24</subnet>
    </lan>
    <opt1>
      <if>vtnet2</if>
      <descr>DMZ</descr>
      <enable>1</enable>
      <ipaddr>10.10.20.1</ipaddr>
      <subnet>24</subnet>
    </opt1>
    <opt2>
      <if>vtnet3</if>
      <descr>PROD</descr>
      <enable>1</enable>
      <ipaddr>10.10.30.1</ipaddr>
      <subnet>24</subnet>
    </opt2>
    <opt3>
      <if>vtnet4</if>
      <descr>BACKUP</descr>
      <enable>1</enable>
      <ipaddr>10.10.40.1</ipaddr>
      <subnet>24</subnet>
    </opt3>
    <opt4>
      <if>vtnet5</if>
      <descr>MONITOR</descr>
      <enable>1</enable>
      <ipaddr>10.10.50.1</ipaddr>
      <subnet>24</subnet>
    </opt4>
  </interfaces>
  <dhcpd>
    <lan>
      <enable>1</enable>
      <range>
        <from>192.168.10.100</from>
        <to>192.168.10.200</to>
      </range>
    </lan>
  </dhcpd>
</opnsense>
EOT
}

# Convert directory to disk with wirt-make-fs utility
resource "null_resource" "make_config_disk" {
  depends_on = [local_file.opnsense_config_xml]
  triggers = {
    xml_change = local_file.opnsense_config_xml.content
  }
  provisioner "local-exec" {
    # Adding "export LIBGUESTFS_BACKEND=direct" to avoid permissions issue 
    command = "export LIBGUESTFS_BACKEND=direct && virt-make-fs --type=vfat --size=+1M ${path.module}/opnsense_data ${path.module}/config.img"
  }
}

resource "libvirt_volume" "config_disk" {
  name   = "config-drive.img"
  pool   = "default"
  source = "${path.module}/config.img"
  depends_on = [null_resource.make_config_disk]
}
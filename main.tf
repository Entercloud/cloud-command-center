
# main.tf

provider "vagrant" {
  version = "2.2.18"
}

resource "vagrant_box" "hashicorp-jammy64" {
  box_name = "ubuntu/jammy64"
}

resource "vagrant_machine" "cloud-workspace-part" {
  provider = "vagrant"
  box      = vagrant_box.ubuntu-jammy64.name
  name     = "cloud-workspace-part"
}

resource "vagrant_machine" "cloud-workspace-part1" {
  provider = "vagrant"
  box      = vagrant_box.ubuntu-jammy64.name
  name     = "cloud-workspace-part1"
}

resource "vagrant_machine" "cloud-workspace-part2" {
  provider = "vagrant"
  box      = vagrant_box.ubuntu-jammy64.name
  name     = "cloud-workspace-part2"
}



# variables.tf

variable "vagrantfile_path" {
  default = "./Vagrantfile"
}

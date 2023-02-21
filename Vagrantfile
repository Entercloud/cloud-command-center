#cloud workcenter


Vagrant.configure("2") do |config|
  # Define the 3 nodes
  (1..3).each do |i|
    config.vm.define "node#{i}" do |node|
      node.vm.box = "ubuntu/jammy64"
      node.vm.hostname = "node#{i}"
      node.vm.network "private_network", ip: "192.168.33.#{i}"
    end
  end
end

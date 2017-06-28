# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.

VM_COUNT = 1 

Vagrant.configure("2") do |config|
  config.vm.box = "csbase-image"

  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  config.hostmanager.ignore_private_ip = false
  config.hostmanager.include_offline = true
  config.vm.provision :hostmanager 

  config.vm.provider :vmware_workstation do |vm,override|
    vm.vmx["memsize"] = "1024"
    vm.vmx["numvcpus"] = "2"
  end

  config.vm.synced_folder ".", "/vagrant"

  (1..VM_COUNT).each do |i|
    config.vm.define "vm#{i}" do |vms|
      vms.vm.network "private_network", type: "dhcp"
      vms.vm.hostname = "vm#{i}"  

      # create zpool for customer-lustre - device
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_zfs' 'cust-pool'"

      # customer-lustre,  args => function_name role fsname pool_name
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'mgs' 'custfs' 'cust-pool'"
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'mdt' 'custfs' 'cust-pool'"
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'ost' 'custfs' 'cust-pool'"
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'client' 'custfs' 'cust-pool'"
      
      # create zpool for cs-lustre - device
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_zfs' 'cs-pool'"

      # cs-lustre, args => function_name role fsname pool_name
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'mdt' 'csfs' 'cs-pool'"
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'ost' 'csfs' 'cs-pool'"
      vms.vm.provision :shell, :path => "bootstrap.sh", :args => "'setup_lustre_role' 'client' 'csfs' 'cs-pool'"

    end
  end
end

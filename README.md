Steps to use this VM -
-----------------------

1. vagrant box created using packer.io should be added in Vagrantfile at line no.
#12   config.vm.box = "csbase-image"

where, "csbase-image" is a vagrant box name

2. command to execute 
(For linux)
# vagrant up --provider=vmware_workstation

(For MAC)
# vagrant up --provider=vmware_fusion


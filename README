Passwordless sudo (plugin - vagrant-hostmanager)
===================================================

To avoid being asked for the password every time the hosts file is updated, enable passwordless sudo for the specific command that hostmanager uses to update the hosts file.

Add the following snippet to the sudoers file (e.g. /etc/sudoers.d/vagrant_hostmanager):

Cmnd_Alias VAGRANT_HOSTMANAGER_UPDATE = /bin/cp <home-directory>/.vagrant.d/tmp/hosts.local /etc/hosts
%<admin-group> ALL=(root) NOPASSWD: VAGRANT_HOSTMANAGER_UPDATE

e.g : 
------

Cmnd_Alias VAGRANT_HOSTMANAGER_UPDATE = /bin/cp /home/jshri/.vagrant.d/tmp/hosts.local /etc/hosts
%wheel ALL=(root) NOPASSWD: VAGRANT_HOSTMANAGER_UPDATE

Replace <home-directory> with your actual home directory (e.g. /home/joe) and <admin-group> with the group that is used by the system for sudo access (usually sudo on Debian/Ubuntu systems and wheel on Fedora/Red Hat systems).

If necessary, add yourself to the <admin-group>:

usermod -aG <admin-group> <user-name>
Replace <admin-group> with the group that is used by the system for sudo access (see above) and <user-name> with you user name

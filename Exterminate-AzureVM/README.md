# Exterminate-AzureVM.ps1

This script deletes all of the (major) components of a VM:
* Compute instance
* OS disk
* All data disks
* All NICs

It works by retrieving the VM object from Azure and then looking at the OSProfile, storageProfile and the networkProfile properties to find the disks and NICs associated with the VM and then deleting them.

This is intended to make cleanup easier when messing around with machines for sandboxing etc.  

Backups of the target VM in a Recovery Vault or similar service, are not affected and will need to be removed manually.

**The deletes are NOT UNDOABLE so use with care.**

## Parameters

### **VirtualMachineName**

The name of the VM to exterminate
vSphere Folder Copy
===================

Tools for dumping and restoring vCenter folders as part of backup or cluster
migration.


Installation
------------

This repository contains two Ruby scripts:

  - dump-vcenter-folders.rb
  - restore-vcenter-folders.rb

The scripts require the [rbvmomi] gem, and have been developed against version
1.11.

  [rbvmomi]: https://rubygems.org/gems/rbvmomi


Usage
-----

The `dump-vcenter-folders.rb` script scans the VM Folder structure of a
datacenter attached to a vCenter instance and prints the structure to
STDOUT in JSON format.

The `restore-vcenter-folders.rb` script reads the JSON produced by
`dump-vcenter-folders.rb` from a file and re-creates the folder structure
inside of a datacenter and relocates VMs by UUID from the
"Discovered virtual machine" folder. The script supports a `--noop` mode
where it will log all operations that would be taken without making any
changes to the vCenter server.

Both scripts respond to `--help` which displays further details on
behavior and options accepted.

# Ideas for using github actions with older verisions of macOS

Run a docker host VM on a local machine.
Use docker compose to setup a set of containers for each version of macOS.
The containers will run actions with the https://github.com/appleboy/ssh-action action
ssh-action will setup the VM host
  ssh into darkstar
  create linked clone of the target macOS vm if it's not already created
  confirm the VM is ready
ssh-action will then use ssh to push the test scripts to the VM and run it.
  use the same break out as the macos vms that can run actions directly

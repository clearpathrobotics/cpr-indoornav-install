# cpr-indoornav-install

This repository contains the post-installation scripts needed to finalize the configuration of an Otto 100 PC. This PC
will serve as an IndoorNav backpack for one of Clearpath's indoor robot platforms (e.g. Dingo, Husky, Ridgeback, Jackal).


## Usage

This script should be run on the IndoorNav backpack PC.

To use this script, first install the OTTO Motors OS version 2.22.4 as described at help.ottomotors.com.

Once the core OS is installed, connect the PC to the internet and run the following commands:
```bash
cd ~
git clone http://github.com/clearpathrobotics/cpr-indoornav-install.git
cd cpr-indoornav-install
bash install.sh
```

The script is interactive, so pay attention.  Some fields, such as the backpack hostname, must be set when configuring
the robot's main PC.

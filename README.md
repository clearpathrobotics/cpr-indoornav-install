# cpr-indoornav-install

This repository contains the post-installation scripts needed to finalize the configuration of an Otto 100 PC. This PC will serve as an IndoorNav
backpack for one of Clearpath's indoor robot platforms (e.g. Dingo, Husky, Ridgeback, Jackal).

For complete documentation refer to https://wiki.clearpathrobotics.com/display/RSES/Bring+up+IndoorNav


## Usage

This script should be run on the IndoorNav backpack PC.

To use this script, first install the Otto OS as described in the link above.  Then run

```bash
cd ~
git clone http://gitlab.clearpathrobotics.com/cpr-indoornav/cpr-indoornav-install
cd cpr-indoornav-install
bash install.sh
```

The script is interactive, so pay attention.  Some fields, such as the backpack hostname, must be set when configuring the main PC.

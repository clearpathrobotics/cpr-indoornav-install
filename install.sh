#!/bin/bash
# This script is intended to be run on the IndoorNav backpack PC immediately after the initial
# OS has been installed using Otto's ISO.
# This script has been tested with Otto 2.22 and may or may not be compatible with other versions
# We plan on supporting 2.24 once that's released
# Older versions are untested

########################################################################################
## Configuration options
## Additional drivers can be flagged for installation here.
## By default we install the e1000e gigabit ethernet driver used by the Vecow SPC-7000
########################################################################################

# Set to 1 to install the e1000e kernel module (needed for the SPC-7000 series PCs
INSTALL_E1000E="1"

# Set to 1 to install the TP-Link kernel module
INSTALL_TP_LINK="0"

# IP address of the ROS Master PC in this robot
ROS_MASTER_IP="10.252.252.100"

OTTO_SOFTWARE_VERSION=$(ls -r /opt/clearpath | grep -E "^[0-9]+\.[0-9]+$" | head -1)
if [ -z "$OTTO_SOFTWARE_VERSION" ];
then
  # newer versions don't have e.g. /opt/clearpath/2.22 anymore, so we need to get the version
  # through a different source
  source /etc/ros/setup.bash
  OTTO_SOFTWARE_VERSION=$(echo $NIX_BUNDLE_TAG | cut -d "." -f 1,2)
fi

########################################################################################
## Helpers
########################################################################################

# available robots; pre-load the user-choice with -1 to indicate undefined
ROBOT_JACKAL=1
ROBOT_HUSKY=2
ROBOT_RIDGEBACK=3
ROBOT_DINGO_D=4
ROBOT_DINGO_O=5
ROBOT_CHOICE=-1

# Color definitions
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
BLU='\033[0;34m'
CYA='\033[0;36m'
NC_='\033[0m' # No Color
REDBG='\033[0;41m'

# Prefixes to put before our log messages
INFO="$BLU[INFO]$NC_"
WARN="$YEL[WARN]$NC_"
ERR_="$RED[ERR ]$NC_"
DBUG="$CYA[DBUG]$NC_"
PASS="$GRN[ OK ]$NC_"
NOTE="$REDBG[NOTE]$NC_"


# Helper functions for logging
log_success() {
  echo -e "${PASS} $@"
}
log_important() {
  echo -e "${NOTE} $@"
}
log_error() {
  echo -e "${ERR_} $@"
}
log_warn() {
  echo -e "${WARN} $@"
}
log_info() {
  echo -e "${INFO} $@"
}
log_debug() {
  echo -e "${DBUG} $@"
}

# used to add a date-samped backup to Otto Motors files we edit or replace
bkup_suffix() {
  echo bkup.$(date +"%Y%m%d%H%M%S")
}

# Script to install the driver for the USB-to-Wifi adapter we sometimes use
# Included for posterity/reference, but unlikely to be needed in production environments
tplink_driver() {
  log_info "Installing tplink driver"
  cd ./rtl8188eus
  sudo apt update
  sudo apt install bc
  sudo rmmod r8188eu.ko
  sudo -i
  echo "blacklist r8188eu" > "/etc/modprobe.d/realtek.conf"
  exit
  make
  sudo make install
  sudo modprobe 8188eu
  cd ..
  log_success "Installation complete"
}

# Script to install the e1000e driver needed for the gigabit ethernet on
# the Vecow SPC-7000 series PCs
e1000e_driver() {
  log_info "Installing e1000e driver"
  if [ "$OTTO_SOFTWARE_VERSION" < "2.28" ];
  then
    cd ./e1000e/src
    make
    sudo make install
    cd ../..
  fi
  sudo modprobe e1000
  log_success "Installation complete"
}

prompt_option() {
  # ask the user to select from a numbered list of options & return their selection
  # $1 is the variable into which the result is returned
  # $2 should be the question to ask the user as a prompt
  # $3+ should be the available options

  local __resultvar=$1
  shift
  local __prompt=$1
  shift
  local __n_options=$#

  echo -e "\e[1;94m${__prompt}\e[0m"
  for (( i=1; $i<=$__n_options; i++ ));
  do
    opt=${!i}
    echo -e "\e[1m[$i] ${opt}\e[0m"
  done

  read answer
  echo "Entered: ${answer}"
  eval $__resultvar="'${answer}'"
}

########################################################################################
## Start of the actual script
########################################################################################
# before we even start, check that we're actually in the right directory!
cd $(dirname $0)
log_debug "Working directory is $(pwd)"

# This script must be run as a normal user, not as root
if [ "$(whoami)" = "root" ];
then
  log_error "This script must not be run as root"
  exit 1
fi

########################################################################################
## Hostname
########################################################################################
while true; do
    read -p "Do you wish to change hostname of IndoorNav computer? Y/n  " yn
    case $yn in
        [Yy]* ) echo "Changing hostname"; clear; sudo dpkg-reconfigure cpr-hostname-cfg; break;;
        [Nn]* ) break;;
        * ) echo "Please answer y or n.";;
    esac
done

########################################################################################
## DNS, systemd-resolved, initial network configuration so we can download
## additional components as necessary later on
########################################################################################

# re-enable systemd-resolved as otherwise we won't have DNS
log_info "Enabling systemd-resolved.service..."
sudo systemctl enable systemd-resolved.service
sudo systemctl unmask systemd-resolved.service
sudo systemctl start systemd-resolved.service

# take down the bridge because we don't need it right now and it will cause problems getting online
log_info "Temporarily taking down sbr0..."
sudo ip link delete sbr0

# detect ethernet interfaces
ETHERNETS=$(ip link | awk -F: '$0 !~ "lo|vb|vir|wl|^[^0-9]"{print $2;getline}')
ETHERNETS=($ETHERNETS)
N_ETHERNETS=${#ETHERNETS[@]}

# ask the user for the port they want to use
while true; do
  prompt_option eth_choice "Choose a physical interface to provide internet access during setup" ${ETHERNETS[@]}
  INTERFACE=${ETHERNETS[$((eth_choice-1))]}  # prompt_option is 1-indexed not 0-indexed

  if [ -z "$INTERFACE" ]; then
    log_error "Invalid selection"
  else
    break
  fi
done

# temporarily disable the existing bridge and get the robot online
log_info "Enabling DHCP on $INTERFACE..."
read -p "       Press ENTER when you have connected an ethernet cable to $INTERFACE"

sudo dhclient $INTERFACE
sudo ip link set up INTERFACE

# verify that we can ping gitlab.clearpathrobotics.com
log_info "Waiting until we can successfully ping gitlab.clearpathrobotics.com..."
while true; do
  if ping -c 1 gitlab.clearpathrobotics.com &> /dev/null; then
    log_success "SUCCESS!"
    break;
  else
    echo -n "."
    sleep 1
  fi
done

########################################################################################
## Additional driver installation
########################################################################################
if [ "$INSTALL_TP_LINK" = "1" ];
then
  tplink_driver
else
  log_debug "Skipping TP-Link installation per user preference."
fi

if [ "$INSTALL_E1000E" = "1" ];
then
  e1000e_driver
else
  log_debug "Skipping e100e installation per user preference."
fi

########################################################################################
## Robot Platform Selection
########################################################################################
log_info "Checking your robot platform..."
prompt_option ROBOT_CHOICE "On which robot are you installing IndoorNav?" "Clearpath Jackal" "Clearpath Husky" "Clearpath Ridgeback" "Clearpath Dingo-D" "Clearpath Dingo-O"

case "${ROBOT_CHOICE}" in
  1)
    platform="jackal"
    platform_simple="jackal"
    ;;
  2)
    platform="husky"
    platform_simple="husky"
    ;;
  3)
    platform="ridgeback"
    platform_simple="ridgeback"
    ;;
  4)
    platform="dingo-d"
    platform_simple="dingo"
    ;;
  5)
    platform="dingo-o"
    platform_simple="dingo"
    ;;
  * )
    log_error "Invalid robot selected. Enter 1 = Jackal, 2 = Husky, 3 = Ridgeback, 4 = Dingo-D, 5 = Dingo-O"
    echo ""
    exit 1
    ;;
esac
log_success "Selected: ${platform}"
echo ""

########################################################################################
## Detect Otto software version, setup .bashrc, clone packages, setup workspace
########################################################################################
log_info "Detected OTTO software version $OTTO_SOFTWARE_VERSION"
echo "source /etc/ros/setup.bash" >> $HOME/.bashrc
echo "source /home/administrator/cpr-indoornav-${platform}/install/setup.bash" >> $HOME/.bashrc

if ping -c1 gitlab.clearpathrobotics.com > /dev/null;
then
  # Clone pre-built parameter workspace if we're running inside clearpath's internal network
  git clone https://gitlab.clearpathrobotics.com/cpr-indoornav/cpr-indoornav-$platform.git
  mv cpr-indoornav-$platform $HOME
  log_success "IndoorNav robot navigation parameters installed!"

  if ! [ -d $HOME/cpr-indoornav-$platform ];
  then
    log_error "Failed to download indoornav parameters for $platform"
    exit 1
  fi
else
  # User must provide the path to the tarball we've emailed them
  echo "Enter the path to the IndoorNav tar.gz file provided by Clearpath Robotics"
  path_ok="0"
  while [ "$path_ok" = "0" ];
  do
    read TARBALL_PATH
    if ! [ -f "$TARBALL_PATH" ];
    then
      log_error "$TARBALL_PATH doesn't exist"
    else
      path_ok="1"
    fi
  done

  # extract the provided file
  tar -xf ${TARBALL_PATH} --directory $HOME
  if [ $? -eq 0 ];
  then
    log_success "IndoorNav robot navigation parameters installed!"
  else
    log_error "Failed to extract $TARBALL_PATH. Please manually extract this file to $HOME later."
  fi
fi


########################################################################################
## Install cpr_indoornav_base to the ROS1 root directory
########################################################################################
ROS_ROOT_DIR=$(echo $ROS_PACKAGE_PATH | rev | cut -d ":" -f 1 | rev)
ROS_ROOT_DIR=$(dirname $ROS_ROOT_DIR)      # remove trailing /share
log_info "Installing cpr-indoornav packages to $ROS_ROOT_DIR"

git clone https://github.com/clearpathrobotics/cpr-indoornav-base.git cpr_indoornav_base
cd cpr_indoornav_base

# Copy the executables
sudo mkdir -p $ROS_ROOT_DIR/lib/cpr_indoornav_base
sudo cp scripts/* $ROS_ROOT_DIR/lib/cpr_indoornav_base

# Copy the meta-data
echo "[INFO] Copying meta-data to $ROS_ROOT_DIR/share/..."
sudo mkdir -p $ROS_ROOT_DIR/share/cpr_indoornav_base
sudo cp package.xml $ROS_ROOT_DIR/share/cpr_indoornav_base

# Copy the launch files
echo "[INFO] Copying launch files to $ROS_ROOT_DIR/share/..."
sudo mkdir -p $ROS_ROOT_DIR/share/cpr_indoornav_base/launch
sudo cp launch/* $ROS_ROOT_DIR/share/cpr_indoornav_base/launch

# Ensure all permissions are correct
echo "[INFO] Setting file permissions"
sudo chmod 755 $ROS_ROOT_DIR/lib/cpr_indoornav_base
sudo chmod 755 $ROS_ROOT_DIR/lib/cpr_indoornav_base/*
sudo chmod 755 $ROS_ROOT_DIR/share/cpr_indoornav_base
sudo chmod 644 $ROS_ROOT_DIR/share/cpr_indoornav_base/*.xml
sudo chmod 755 $ROS_ROOT_DIR/share/cpr_indoornav_base/launch
sudo chmod 644 $ROS_ROOT_DIR/share/cpr_indoornav_base/launch/*.launch
cd ..

########################################################################################
## Bridge & hosts configuration, setup.bash, setup-remote.bash
########################################################################################
log_info "Setting the network configuration"
sudo rm /etc/netplan/*.yaml
sudo cp ./netplan/*.yaml /etc/netplan
#sudo netplan apply

log_info "Exporting ROS settings"
read -p "What is the HOSTNAME of the ROBOT computer? " robot_pc_hostname

echo "$ROS_MASTER_IP $robot_pc_hostname" | sudo tee -a /etc/hosts
echo "export ROS_MASTER_URI=http://$robot_pc_hostname:11311 # Robot PC’s hostname" | tee -a $HOME/.bashrc
# If the user changed their hostname above then the $HOSTNAME envar may not be correct anymore
# read the update /etc/hostname file to be safe!
echo "export ROS_HOSTNAME=$(cat /etc/hostname)" | tee -a $HOME/.bashrc

sudo bash -c "cat > /etc/ros/setup-remote.bash" <<EOF
#!/bin/bash

source /etc/ros/setup.bash
export ROS_MASTER_URI=http://$robot_pc_hostname:11311

exec "\$@"
EOF
sudo chmod 755 /etc/ros/setup-remote.bash

# Add our workspace to the sources
echo "source /home/administrator/cpr-indoornav-${platform}/install/setup.bash" | sudo tee -a /etc/ros/setup.bash
echo "export ENABLE_OBJECT_TRACKING=false"                                     | sudo tee -a /etc/ros/setup.bash
echo "export ENABLE_BAGGING=false"                                             | sudo tee -a /etc/ros/setup.bash
echo "export ENABLE_AUTONOMY_ADAPTOR=true"                                     | sudo tee -a /etc/ros/setup.bash
echo "export ENABLE_FLEET_ADAPTOR=true"                                        | sudo tee -a /etc/ros/setup.bash
echo "export ENABLE_PLATFORM_ADAPTOR=false"                                    | sudo tee -a /etc/ros/setup.bash
echo "export ROBOT_REQUIRE_NIMBUS=false"                                       | sudo tee -a /etc/ros/setup.bash
echo "export BRIDGE_INTF=att0"                                                 | sudo tee -a /etc/ros/setup.bash
echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"                            | sudo tee -a /etc/ros/setup.bash
echo "export CYCLONEDDS_URI=file:///home/administrator/cyclone_dds.xml"        | sudo tee -a /etc/ros/setup.bash
cp ros/cyclone_dds.xml $HOME/cyclone_dds.xml

log_success "ROS settings saved"

########################################################################################
## NTP Configuration (Chrony)
########################################################################################
#update the chrony config file to sync with ubuntu servers
# it looks like Otto does some weird stuff here, so nuke it all and start again
log_info "Configuring NTP sources..."
sudo rm /etc/chrony/*.conf*    # there's .conf, .conf.robot and .conf.robot-orig
sudo cp ntp/chrony.conf /etc/chrony/chrony.conf
sudo rm /etc/init.d/chrony.robot*
sudo systemctl restart chronyd
chronyc -a sources #this should list the new for sources for time sync
log_success "NTP configured"

########################################################################################
## Firewall & port-forwarding
########################################################################################
#disable firewall after reboot
log_info "Disabling ufw..."
sudo systemctl disable ufw
sudo systemctl stop ufw
sudo ufw status #to check the status
log_success "Firewall disabled"

########################################################################################
## Rebranding, Entpoint menu modification
########################################################################################
log_info "Applying rebranding & customized menus"

# edit the Otto App branding to use Clearpath logos & branding
BRANDED_FILES=$(grep -l -r -i "otto app" $ROS_ROOT_DIR/share)
for f in $BRANDED_FILES;
do
  sudo sed -i.$(bkup_suffix) 's/OTTO App/Clearpath App/' $f
done

# replace logo SVG files
LOGO_FILES=$(sudo find / -name Logo_OTTO_Motors_90_40.svg)
for f in $LOGO_FILES;
do
  sudo mv $f $f.$(bkup_suffix)
  sudo cp ./assets/clearpath_logo_90_40.svg $f
done

# Depending on the version we need to modify different directories
# NOTE 2.24+ is untested and may not work!
ASSETS_DIR=""
DEFAULT_MAP_DIR=""
if [ "$OTTO_SOFTWARE_VERSION" == "2.22" ];
then
  ASSETS_DIR=/opt/clearpath/${OTTO_SOFTWARE_VERSION}/share/atlas_mapper/public/node_modules/atlas_common/assets
  DEFAULT_MAP_DIR=/opt/clearpath/$OTTO_SOFTWARE_VERSION/share/cpr_robot_web_api/defaultMap
elif [ "$OTTO_SOFTWARE_VERSION" == "2.24" ] ||
     [ "$OTTO_SOFTWARE_VERSION" == "2.26" ];
then
  ASSETS_DIR=/opt/clearpath/apps/cpr-otto-app/public/node_modules/atlas_common/assets
  DEFAULT_MAP_DIR=/opt/clearpath/apps/cpr-robot-web-api/defaultMap
else
  # 2.28
  # TODO
  ASSETS_DIR=
  DEFAULT_MAP_DIR=
fi

# Remove unnecessary items from the Endpoints menu
sudo mv $DEFAULT_MAP_DIR/places.json $DEFAULT_MAP_DIR/places.json.$(bkup_suffix)
sudo mv $DEFAULT_MAP_DIR/recipes.json $DEFAULT_MAP_DIR/recipes.json.$(bkup_suffix)
sudo cp assets/places.json $DEFAULT_MAP_DIR/places.json
sudo cp assets/recipes.json $DEFAULT_MAP_DIR/recipes.json

# replace the SVG of the robot model (if we have an appropriate graphic)
# we replace both the default OTTO 1500 and the fallback OTTO Unknown graphics
if [ -f assets/${platform}_normal.svg ];
then
  log_info "Replacing robot vector artwork..."
  DIR=$ASSETS_DIR/map/v2/otto_1500
  sudo mv $DIR $DIR.$(bkup_suffix)
  sudo mkdir $DIR
  sudo cp assets/${platform}_lights_detailed.svg $DIR/OTTO1500_lights_detailed.svg
  sudo cp assets/${platform}_lights_normal.svg $DIR/OTTO1500_lights_normal.svg
  sudo cp assets/${platform}_lights_simple.svg $DIR/OTTO1500_lights_simple.svg
  sudo cp assets/${platform}_detailed.svg $DIR/OTTO1500_detailed.svg
  sudo cp assets/${platform}_normal.svg $DIR/OTTO1500_normal.svg
  sudo cp assets/${platform}_simple.svg $DIR/OTTO1500_simple.svg

  DIR=$ASSETS_DIR/map/v2/otto_unknown
  sudo mv $DIR $DIR.$(bkup_suffix)
  sudo mkdir $DIR
  sudo cp assets/${platform}_lights_detailed.svg $DIR/OTTOUnknown_lights_detailed.svg
  sudo cp assets/${platform}_lights_normal.svg $DIR/OTTOUnknown_lights_normal.svg
  sudo cp assets/${platform}_lights_simple.svg $DIR/OTTOUnknown_lights_simple.svg
  sudo cp assets/${platform}_detailed.svg $DIR/OTTOUnknown_detailed.svg
  sudo cp assets/${platform}_normal.svg $DIR/OTTOUnknown_normal.svg
  sudo cp assets/${platform}_simple.svg $DIR/OTTOUnknown_simple.svg
else
  log_warn "No vector images for $platform in assets/*; robot model will appear as an OTTO 1500"
fi

# Replace the charger graphics
DIR=$ASSETS_DIR/map/v2/otto_100_charger
sudo mv $DIR $DIR.$(bkup_suffix)
sudo mkdir $DIR
sudo mkdir $DIR/Detailed
sudo mkdir $DIR/Normal
sudo mkdir $DIR/Simple
sudo cp assets/husky-dock.svg $DIR/Detailed/OTTO100charger_detailed_default.svg
sudo cp assets/husky-dock.svg $DIR/Normal/OTTO100charger_normal_default.svg
sudo cp assets/husky-dock.svg $DIR/Simple/OTTO100charger_simple_default.svg
sudo cp assets/husky-dock-hover.svg $DIR/Detailed/OTTO100charger_detailed_hover.svg
sudo cp assets/husky-dock-hover.svg $DIR/Normal/OTTO100charger_normal_hover.svg
sudo cp assets/husky-dock-hover.svg $DIR/Simple/OTTO100charger_simple_hover.svg
sudo cp assets/husky-dock-selected.svg $DIR/Detailed/OTTO100charger_detailed_selected.svg
sudo cp assets/husky-dock-selected.svg $DIR/Normal/OTTO100charger_normal_selected.svg
sudo cp assets/husky-dock-selected.svg $DIR/Simple/OTTO100charger_simple_selected.svg

log_success "Rebranding complete"

# make specific changes for webviz
log_info "Updating WebViz configuration..."
# Remove the left & right scan as they do not exist
sudo cp $ROS_ROOT_DIR/share/cpr_webviz_host/launch/converter.launch $ROS_ROOT_DIR/share/cpr_webviz_host/launch/converter.launch.$(bkup_suffix)
sudo sed -i '/webviz_throttle_left_scan/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/converter.launch
sudo sed -i '/webviz_throttle_right_scan/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/converter.launch
# Remove topics that do not exist
sudo cp $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch.$(bkup_suffix)
sudo sed -i '/move_base\/GraphPlanner\/\*/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/webviz_realtime_converter\/slam\/magnetic_lines/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/left\/scan/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/right\/scan/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/honeycomb\/pointcloud/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/honeycomb\/points/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
sudo sed -i '/lift_controller/d' $ROS_ROOT_DIR/share/cpr_webviz_host/launch/rosbridge.launch
# Logo & branding swap
sudo cp $ROS_ROOT_DIR/share/cpr_webviz_host/landing/index.html $ROS_ROOT_DIR/share/cpr_webviz_host/landing/index.html.$(bkup_suffix)
sudo sed -i 's/href="http:\/\/ottomotors.com\/"/href="http:\/\/clearpathrobotics.com\/"/g' $ROS_ROOT_DIR/share/cpr_webviz_host/landing/index.html
sudo sed -i 's/src="otto_motors_light.svg" alt="OTTO Motors"/src="clearpath_logo.svg" alt="Clearpath Robotics"/g' $ROS_ROOT_DIR/share/cpr_webviz_host/landing/index.html
sudo cp assets/clearpath_logo_90_40.svg $ROS_ROOT_DIR/share/cpr_webviz_host/landing/clearpath_logo.svg
# Done!
log_success "WebViz configuration complete"

########################################################################################
## Reboot to finish!
########################################################################################
log_info "You must reboot to finish the setup"
while true; do
    read -p "Reboot now? Y/n  " yn
    case $yn in
        [Yy]* ) log_info "Rebooting!"; sudo shutdown -r now;;
        [Nn]* ) log_important "Reboot deferred. Note that some configurations will not apply until after rebooting."; break;;
        * ) log_error "Please answer y or n.";;
    esac
done

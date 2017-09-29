#!/bin/bash
#
# Prep a RHEL server for SAP HANA
# by: Raj W
# Version: 0.1.1
# Updated: 9/28/2017
#

# Setup ANSI colors. Yeah, that's the way I roll!
green='\033[1;32m'  # ${green}
cyan='\033[1;36m'   # ${cyan}
red='\033[1;31m'	  # ${red}
yellow='\033[1;33m' # ${yellow}
nc='\033[0m'		    # ${nc} - no color
el='\033[2K'        # ${el} - erase line

# Check if running as sudo or root
if (( $EUID != 0 )); then
    echo -e "${red}ERR: You need to run this as root.${nc}"
    exit 1
fi

# Add the RHEL SAP repository
echo "[saphana-x86_64]" > /etc/yum.repos.d/virtustream-sap.repo
echo "name=Virtustream Custom SAP Repository (SAPHANA-x86_64)" >> /etc/yum.repos.d/virtustream-sap.repo
echo "mirrorlist=https://a06nus014cds001.xstream360.cloud/pulp/mirror/SAPHANA-x86_64" >> /etc/yum.repos.d/virtustream-sap.repo
echo "enabled=1" >> /etc/yum.repos.d/virtustream-sap.repo
echo "gpgcheck=0" >> /etc/yum.repos.d/virtustream-sap.repo
echo "sslverify=0" >> /etc/yum.repos.d/virtustream-sap.repo
#
# Clean the yum database
echo -ne "${cyan}Clean the yum database. "
yum clean all &> /dev/null
echo -e "${green}[done]${nc}"
#
# Pull the updated RPM lists
echo -ne "${cyan}Reloading RPM database. "
yum check-update &> /dev/null
echo -e "${green}[done]${nc}"

# Remove newer tuned because -sapconf- wants one rev older
# I think that the repository is borked but I don't have time
# to deal with that right now.
# rpm -e tuned-2.7.1-3.el7_3.2 &> /dev/null
#
# Install packages
echo -e "\n${cyan}Checking for SAP prerequisites:${nc}"
# I put the 'sleep' in so the user can see what is happening. The process is actually really fast.
# function isrpminst () {
#        #STRLEN=${#RPMQ}
#        echo -en "\r${el}"
#        if yum list installed "$1" >/dev/null 2>&1; then
#                echo -en "${green}[$1] RPM installed${nc}"
#                sleep 0.4
#        else
#                echo -e "${red}[$1] RPM not installed${nc}"
#                sleep 0.4
#                RPMINSTLIST="$1 $RPMINSTLIST"
#        fi
#}

#SAPRPMS=(xfsprogs audit-libs compat-openldap gtk2 libicu \
yum -y install xfsprogs audit-libs compat-openldap gtk2 libicu
# yum -y install xulrunner sudo tuned-2.7.1-3.el7_3.1 tcsh libssh2 expect cairo graphviz 
yum -y install xulrunner tuned tcsh libssh2 expect cairo graphviz 
yum -y install iptraf-ng nfs-utils expect numactl
yum -y install rsyslog openssl098e openssl 
yum -y install libcanberra-gtk2 libtool-ltdl
yum -y install xorg-x11-xauth xorg-x11-apps compat-libstdc++-33 cyrus-sasl-lib
yum -y install keyutils-libs libaio libcom_err libevent libuuid
yum -y install openldap zlib tmpwatch icedtea-web sapconf
yum -y install compat-locales-sap compat-sap-c++
yum -y install PackageKit-gtk3-module
yum -y install libcanberra-gtk2 uuidd
yum -y install libtool-ltdl
yum -y install net-tools
yum -y install bind-utils
yum -y install compat-sap-c++-5
yum -y install compat-sap-c++-6


# Activate SAP HANA Specific Tuned Profiles
yum -y install tuned-profiles-sap-hana &> /dev/null
systemctl start tuned &> /dev/null
systemctl enable tuned &> /dev/null

if lspci | grep -qi vmware; then
   echo "{cyan}Running on VMware.  ${green}Applying VMware SAP HANA tuned settings.${nc}"
   tuned-adm profile sap-hana-vmware
else
   echo "{cyan}Running on hardware.  ${green}Applying bare metal SAP HANA tuned settings.${nc}"
   tuned-adm profile sap-hana
fi

# Disable Automatic NUMA Balancing
echo -ne "{cyan}Disable Automatic NUMA Balancing"
if grep --quiet "release 7" /etc/redhat-release; then
	systemctl stop numad
  systemctl disable numad
else
  chkconfig numad off &> /dev/null
  service numad stop &> /dev/null
fi

# Check if the sap_hana.conf file exists.
# If not, create it.
SHFILE="/etc/sysctl.d/sap_hana.conf"
if [ -f "$SHFILE" ]; then
   echo "File $SHFILE exists."
   
   # Update the kernel.numa_balancing value
   if grep -q 'kernel.numa_balancing=0' $SHFILE; then
	   echo "Updating $SHFILE value"
	   sed -i 's/kernel.numa_balancing.*/kernel.numa_balancing=0/' $SHFILE
   else
    echo "Adding [kernel.numa_balancing=0] value"
	  echo "kernel.numa_balancing=0" >> $SHFILE
   fi  
else
   echo "File $SHFILE does not exist. Creating $SHFILE ." >&2
   echo "kernel.numa_balancing=0" > /etc/sysctl.d/sap_hana.conf
fi
echo -e "${green}[done]${nc}"

#for i in "${SAPRPMS[@]}"
#do
#   :
#        isrpminst $i
#done
#echo -en "\r${el}"

#echo "-------------------------------------------------------------"
#echo -e "\n${yellow}RPMs to install:${cyan} $RPMINSTLIST${nc}\n"
#echo "-------------------------------------------------------------"
#sleep 5

#yum -y install $RPMINSTLIST$

# Enable and start the uuidd daemon
if grep --quiet "release 7" /etc/redhat-release; then
  echo -ne "${cyan}RHEL7: Enable 'uuidd' daemon... "
  systemctl enable uuidd &> /dev/null
  systemctl start uuidd &> /dev/null
else  
  echo -ne "${cyan}RHEL6: Enable 'uuidd' daemon... "
  chkconfig uuidd on &> /dev/null
  service uuidd start &> /dev/null
fi
echo -e "${green}[done]${nc}"

#
# Make sure NTP is installed and operational
yum -y install ntp ntpdate &> /dev/null
chkconfig ntpd on &> /dev/null
service ntpd stop &> /dev/null
ntpdate 0.us.pool.ntp.org &> /dev/null
service ntpd start &> /dev/null
#
# Configure SELinux. SecOps requires a minimum of 'permissive'.
# Permissive permissions does not block anything.
echo -ne "${cyan}SAP does not support SELinux. Change SELinux to permissive... "
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
sed -i 's/^SELINUX=disabled/SELINUX=permissive/g' /etc/sysconfig/selinux
echo -e "${green}[done]${nc}"
#
# Disable kdump
if grep --quiet "release 7" /etc/redhat-release; then
  echo -ne "${cyan}RHEL7: Disable kdump... "
  systemctl stop kdump.service
  systemctl disable kdump.service
else
  echo -ne "${cyan}RHEL6: Disable kdump... "
  service kdump stop &> /dev/null
  chkconfig kdump off &> /dev/null
fi
echo -e "${green}[done]${nc}"
#
#
# Setup SSL and Crypto symbolic links for compatibility
echo -ne "${cyan}Setup SSL and Crypto symbolic links for compatibility.{nc}"
sslver=$(ls /usr/lib64/libssl.so.1.*)
ln -s $sslver /usr/lib64/libssl.so.1.0.1
cryptver=$(ls /usr/lib64/libcrypto.so.1.*)
ln -s $cryptver /usr/lib64/libcrypto.so.1.0.1
echo -e "${green}[done]${nc}"
#
# Setup sapsys limits
echo -ne "${cyan}Creating 99-sapsys.conf with SAP suggested settings... "
echo "@sapsys hard nofile 32800" > /etc/security/limits.d/99-sapsys.conf
echo "@sapsys soft nofile 32800" >> /etc/security/limits.d/99-sapsys.conf
echo "@sapsys soft nproc unlimited" >> /etc/security/limits.d/99-sapsys.conf
echo "@dba soft nproc unlimited" >> /etc/security/limits.d/99-sapsys.conf
echo -e "${green}[done]${nc}"
#
# Disable crash reporting
if grep --quiet "release 7" /etc/redhat-release; then
  echo -ne "${cyan}RHEL7: Disable crash reporting... "
  systemctl disable abrtd &> /dev/null
  systemctl disable abrt-ccpp &> /dev/null
  systemctl stop abrtd &> /dev/null
  systemctl stop abrt-ccpp &> /dev/null
else  
  echo -ne "${cyan}RHEL6: Disable crash reporting... "
  chkconfig abrtd off &> /dev/null
  chkconfig abrt-ccpp off &> /dev/null
  service abrtd stop &> /dev/null
  service abrt-ccpp stop &> /dev/null
fi
echo -e "${green}[done]${nc}"

#
# Disable core dumps
echo -ne "${cyan}Disable core dumps... "
echo "* soft core 0" >> /etc/security/limits.conf
echo "* hard core 0" >> /etc/security/limits.conf
echo -e "${green}[done]${nc}"

# RHEL7 - /etc/tmpfiles.d/sap.conf - Clean up the /tmp directory
if grep --quiet "release 7" /etc/redhat-release; then
  echo -ne "${cyan}RHEL7 detected - Creating /etc/tmpfiles.d/sap.conf to clean up temp files... "
  echo "# systemd tmpfiles exclude file for SAP" > /etc/tmpfiles.d/sap.conf
  echo "# SAP software stores some important files" >> /etc/tmpfiles.d/sap.conf
  echo "# in /tmp which should not be deleted" >> /etc/tmpfiles.d/sap.conf
  echo "/etc/tmpfiles.d/sap.conf" >> /etc/tmpfiles.d/sap.conf
  echo "# Exclude SAP socket and lock files" >> /etc/tmpfiles.d/sap.conf
  echo "x /tmp/.sap*" >> /etc/tmpfiles.d/sap.conf
  echo "# Exclude HANA lock file" >> /etc/tmpfiles.d/sap.conf
  echo "x /tmp/.hdb*lock" >> /etc/tmpfiles.d/sap.conf
  echo -e "${green}[done]${nc}"
fi

echo -e "${yellow}--[ ${cyan}Validate hostname output ${yellow}]------------------${nc}"
echo -e "${cyan}Validate hostname output:"
echo -en "${cyan}hostname: ${green}" & hostname
echo -en "${cyan}hostname -s: ${green}" & hostname -s
echo -en "${cyan}hostname -f: ${green}" & hostname -f
echo -en "${cyan}hostname -d: ${green}" & hostname -d
echo -e "${yellow}------------------------------------------------${nc}"
echo -e "${yellow}<eol>${nc}"


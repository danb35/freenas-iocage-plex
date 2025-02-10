#!/bin/sh
# Build an iocage jail under TrueNAS CORE 13.3 using the current release of Plex Media Server
# https://github.com/danb35/freenas-iocage-plex

JAIL_IP=""
DEFAULT_GW_IP=""
NETMASK=""
USE_HW_TRANSCODE="0"
VNET="on"
POOL_PATH=""
PLEX_CONFIG_PATH=""
PLEX_MEDIA_PATH=""
INTERFACE="vnet0"
# BUGBUG In FreeNAS 11.3-U1, a 'plex' jail would not install pkg; any other name would
# This was caused by the presence of another jail that had been named 'plex' at one
# point. Might be CPE or FreeNAS. Since this script is used to migrate data off an
# old plugin, side-stepping issue by naming jail 'pms'.  
JAIL_NAME="pms"
USE_BETA=0
USE_BASEJAIL="-b"
PLEXPKG=""
HW_TRANSCODE_RULESET="10"
DEVFS_RULESET=""
RULESET_SCRIPT="/root/scripts/plex-ruleset.sh"

# $1 = devfs ruleset number
# $2 = script location
# Creates script for devfs ruleset and i915kms, causes it to execute on boot, and loads it
createrulesetscript() {
  if [ -z "$1" ] ; then
    echo "ERROR: No plex devfs ruleset number specified. This is an internal script error."
    return 1
  fi
  if [ -z "$2" ] ; then
    echo "ERROR: No plex ruleset script location specified. This is an internal script error."
    return 1
  fi
  if [ -z "$(echo ${RELEASE} | grep '12.1')" ] && [ -z "$(echo ${RELEASE} | grep '11.3')" ] ; then
    echo "This script only knows how to enable hardware transcode in FreeNAS 11.3 and TrueNAS 12.0"
    return 1
  fi
  IGPU_MODEL=$(lspci -q | grep Intel | grep Graphics) 
  if [ ! -z "${IGPU_MODEL}" ] ; then
    echo "Found Intel GPU model " ${IGPU_MODEL} ", this bodes well."
    if [ -z "$(kldstat | grep i915kms.ko)" ] ; then
      kldload /boot/modules/i915kms.ko
      if [ -z "$(kldstat | grep i915kms.ko)" ] ; then
        echo "Unable to load driver for Intel iGPU, please verify it is supported in this version of FreeNAS/TrueNAS"
        return 1
      fi
    fi
  else
    echo "The naive Intel iGPU check didn't find one."
    echo "If you know you have supported hardware, please send the authors of this script"
    echo "the output of \"lspci\" on your system, and we'll improve the detection logic."
    return 1
  fi 
  if [ ! -f $2 ] ; then
    echo "Creating script file" $2 
    cat > $2 <<EOF
#!/bin/sh

echo '[devfsrules_bpfjail=101]
add path 'bpf*' unhide

[plex_drm=$1]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add include \$devfsrules_jail
add include \$devfsrules_bpfjail
add path 'dri*' unhide
add path 'dri/*' unhide
add path 'drm*' unhide
add path 'drm/*' unhide' >> /etc/devfs.rules

service devfs restart

kldload /boot/modules/i915kms.ko
EOF
  chmod +x $2
  else
    if [ -z "$(grep "plex_drm=$1" $2)" ]; then
     echo "Script file $2 exists, but does not configure devfs ruleset $1 for Plex as expected."
     return 1
    fi
  fi
  if [ -z "$(devfs rule -s $1 show)" ]; then
    echo "Executing script file $2"
    $2
  fi
  if [ -z "$(midclt call initshutdownscript.query | grep $2)" ]; then
    echo "Setting script $2 to execute on boot"
    midclt call initshutdownscript.create "{\"type\": \"SCRIPT\", \"script\": \"$2\", \"when\": \"POSTINIT\", \"enabled\": true, \"timeout\": 10}"
  fi
  return 0
}

SCRIPT=$(readlink -f "$0")

SCRIPTPATH=$(dirname "${SCRIPT}")
. "${SCRIPTPATH}"/plex-config
CONFIGS_PATH="${SCRIPTPATH}"/configs
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.3-RELEASE, change to 13.4-RELEASE
if [ "${RELEASE}" = "13.3-RELEASE" ]; then
  RELEASE="13.4-RELEASE"
fi 

# Check for plex-config and set configuration
if ! [ -e "${SCRIPTPATH}"/plex-config ]; then
  echo "${SCRIPTPATH}/plex-config must exist."
  exit 1
fi

# Check that necessary variables were set by plex-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${NETMASK}" ]; then
  echo 'Netmask not set, defaulting to /24 (255.255.255.0)'
  NETMASK="24"
fi

if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi
# If PLEX_CONFIG_PATH isn't specified in plex-config, set it
if [ -z "${PLEX_CONFIG_PATH}" ]; then
  echo "Plex metadata path not set, defaulting to ${POOL_PATH}/plex_data"
  PLEX_CONFIG_PATH="${POOL_PATH}"/plex_data
fi
if [ -z "${PLEX_MEDIA_PATH}" ]; then
  echo "Plex media path not set, please mount media directory manually when done"
else
  echo "Plex media path is ${PLEX_MEDIA_PATH}, the script will mount this into /media inside the Plex jail"
fi

if [ -z "${USE_HW_TRANSCODE}" ]; then
  USE_HW_TRANSCODE="0"
fi
if [ $USE_HW_TRANSCODE -eq 0 ]; then
  echo "Not configuring hardware transcode"
else
  if createrulesetscript ${HW_TRANSCODE_RULESET} ${RULESET_SCRIPT}; then
    echo "Configuring hardware transcode with ruleset ${HW_TRANSCODE_RULESET}."
    DEVFS_RULESET="devfs_ruleset=${HW_TRANSCODE_RULESET}"
  else
    echo "Not configuring hardware transcode automatically, please do it manually."
    DEVFS_RULESET=""
    USE_HW_TRANSCODE="0"
  fi
fi

if [ $USE_BETA -eq 1 ]; then
	echo "Using beta-release plexmediaserver code"
	PLEXPKG="plexmediaserver-plexpass"
else
	echo "Using stable-release plexmediaserver code"
	PLEXPKG="plexmediaserver"
fi
# Create jail
echo "Creating jail "${JAIL_NAME}". This may take a minute, please be patient."
if ! iocage create --name "${JAIL_NAME}" -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL} ${DEVFS_RULESET}
then
	echo "Failed to create jail"
	exit 1
fi

iocage exec "${JAIL_NAME}" mkdir /config
iocage exec "${JAIL_NAME}" mkdir /configs
iocage exec "${JAIL_NAME}" chmod 777 /tmp
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pkg/repos
iocage exec "${JAIL_NAME}" cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/
iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/latest/" /usr/local/etc/pkg/repos/FreeBSD.conf
mkdir -p "${PLEX_CONFIG_PATH}"
chown -R 972:972 "${PLEX_CONFIG_PATH}"
iocage fstab -a "${JAIL_NAME}" "${PLEX_CONFIG_PATH}" /config nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${CONFIGS_PATH}" /configs nullfs rw 0 0
if [ -n "${PLEX_MEDIA_PATH}" ]; then
  iocage fstab -a "${JAIL_NAME}" "${PLEX_MEDIA_PATH}" /media nullfs rw 0 0
fi
iocage exec "${JAIL_NAME}" cp /configs/pkg.conf /usr/local/etc
if ! iocage exec "${JAIL_NAME}" pkg install ${PLEXPKG}
then
	echo "Failed to install ${PLEXPKG} package"
	iocage stop "${JAIL_NAME}"
	iocage destroy -f "${JAIL_NAME}"
	exit 1
fi
iocage exec "${JAIL_NAME}" rm /usr/local/etc/pkg.conf
if [ $USE_BETA -eq 1 ]; then
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_support_path="/config"
else
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_support_path="/config"
  sed -i '' "s/_plexpass//" "${CONFIGS_PATH}"/update_packages
fi

iocage exec "${JAIL_NAME}" crontab /configs/update_packages
iocage fstab -r "${JAIL_NAME}" "${CONFIGS_PATH}" /configs nullfs rw 0 0
iocage exec "${JAIL_NAME}" rm -rf /configs
if [ $USE_HW_TRANSCODE -ne 0 ]; then
   iocage exec "${JAIL_NAME}" pw groupmod -n video -m plex
fi
if [ -z "${PLEX_MEDIA_PATH}" ]; then
  iocage stop "${JAIL_NAME}"
else
  if [ $USE_HW_TRANSCODE -ne 0 ] && [ ! -z "$(echo ${RELEASE} | grep '11.3')" ] ; then
  # Work around a FreeBSD 11.3 devfs issue
    iocage stop "${JAIL_NAME}"
    service devfs restart
    iocage start "${JAIL_NAME}"
  else
    iocage restart "${JAIL_NAME}"
  fi
fi

echo "Installation Complete!"
if [ -z "${PLEX_MEDIA_PATH}" ]; then 
  echo "Mount your media folder into the jail, then start the jail."
fi
echo "Log in and configure your server by browsing to:"
echo "http://$JAIL_IP:32400/web"

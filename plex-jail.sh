#!/bin/sh
# Build an iocage jail under FreeNAS 11.2/11.3 using the current release of Plex Media Server
# https://github.com/danb35/freenas-iocage-plex

JAIL_IP=""
DEFAULT_GW_IP=""
NETMASK=""
VNET="on"
POOL_PATH=""
PLEX_CONFIG_PATH=""
INTERFACE="vnet0"
# BUGBUG In FreeNAS 11.3-U1, a 'plex' jail would not install pkg; any other name would
# This was caused by the presence of another jail that had been named 'plex' at one
# point. Might be CPE or FreeNAS. Since this script is used to migrate data off an
# old plugin, side-stepping issue by naming jail 'pms'.  
JAIL_NAME="pms"
USE_BETA=0
USE_BASEJAIL="-b"
PLEXPKG=""

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
. "${SCRIPTPATH}"/plex-config
CONFIGS_PATH="${SCRIPTPATH}"/configs
RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g" | sed "s/-p[0-9]*//")

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

if [ $USE_BETA -eq 1 ]; then
	echo "Using beta-release plexmediaserver code"
	PLEXPKG="plexmediaserver_plexpass"
else
	echo "Using stable-release plexmediaserver code"
	PLEXPKG="plexmediaserver"
fi
# Create jail
if ! iocage create --name "${JAIL_NAME}" -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi

iocage exec "${JAIL_NAME}" mkdir /config
iocage exec "${JAIL_NAME}" mkdir /configs
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pkg/repos
iocage exec "${JAIL_NAME}" cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/
iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/latest/" /usr/local/etc/pkg/repos/FreeBSD.conf
mkdir -p "${PLEX_CONFIG_PATH}"
chown -R 972:972 "${PLEX_CONFIG_PATH}"
iocage fstab -a "${JAIL_NAME}" "${PLEX_CONFIG_PATH}" /config nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${CONFIGS_PATH}" /configs nullfs rw 0 0
iocage exec "${JAIL_NAME}" cp /configs/pkg.conf /usr/local/etc
if ! iocage exec "${JAIL_NAME}" pkg install ${PLEXPKG}
then
	echo "Failed to install ${PLEXPKG} package"
	iocage stop "${JAIL_NAME}"
	iocage destroy -f "${JAIL_NAME}"
	exit 1
fi
iocage exec "${JAIL_NAME}" rm /usr/local/etc/pkg.conf
if [ $USE_PLEXPASS -eq 1 ]; then
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_support_path="/config"
else
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_support_path="/config"
  sed -i '' "s/-plexpass//" "${CONFIGS_PATH}"/update_packages
fi

iocage exec "${JAIL_NAME}" crontab /configs/update_packages
iocage fstab -r "${JAIL_NAME}" "${CONFIGS_PATH}" /configs nullfs rw 0 0
iocage exec "${JAIL_NAME}" rm -rf /configs
iocage restart "${JAIL_NAME}"

echo "Installation Complete!"
echo "Log in and configure your server by browsing to:"
echo "http://$JAIL_IP:32400/web"

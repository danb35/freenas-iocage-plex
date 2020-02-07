#!/bin/sh
# Build an iocage jail under FreeNAS 11.2/11.3 using the current release of Plex Media Server
# https://github.com/danb35/freenas-iocage-plex

JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
PLEX_CONFIG_PATH=""
JAIL_NAME="plex"
USE_PLEXPASS=0

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
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

# If PLEX_CONFIG_PATH isn't specified in plex-config, set it
if [ -z "${PLEX_CONFIG_PATH}" ]; then
  PLEX_CONFIG_PATH="${POOL_PATH}"/plex_data
fi

if [ $USE_PLEXPASS -eq 1 ]; then
	cat <<__EOF__ >/tmp/pkg.json
	{
	  "pkgs":[
	  "plexmediaserver-plexpass"
	  ]
	}
__EOF__
else
	cat <<__EOF__ >/tmp/pkg.json
	{
	  "pkgs":[
	  "plexmediaserver"
	  ]
	}
__EOF__
fi

# Create jail
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

iocage exec "${JAIL_NAME}" mkdir /config
iocage exec "${JAIL_NAME}" mkdir /configs
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pkg/repos
iocage exec "${JAIL_NAME}" cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/
iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/latest/" /usr/local/etc/pkg/repos/FreeBSD.conf
mkdir -p "${PLEX_CONFIG_PATH}"
chown -R 972:972 "${PLEX_CONFIG_PATH}"
iocage fstab -a "${JAIL_NAME}" "${PLEX_CONFIG_PATH}" /config nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${CONFIGS_PATH}" /configs nullfs rw 0 0
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
iocage exec "${JAIL_NAME}" pkg upgrade -y
iocage restart "${JAIL_NAME}"

echo "Installation Complete!"
echo "Log in and configure your server by browsing to:"
echo "http://$JAIL_IP:32400/web"

# freenas-iocage-plex
Scripted installation of Plex Media Server in a FreeNAS jail

## Description
This is a simple script to automate installation of Plex Media Server in a FreeNAS jail, following current best practices.  It will create a jail, install Plex Media Server (with or without PlexPass), configure Plex to store its preferences and metadata outside the jail, and create a cron job to update the installed packages every week using the FreeBSD `latest` repository rather than `quarterly`.

This script **does not** address media storage for the jail.  That will ordinarily be one or more external datasets on your FreeNAS server, which you can mount to a desired location inside the jail.  Because this depends very much on your data layout and personal preferences, this is left up to the user.

## Installation
On your FreeNAS server, change to a convenient directory, and download this script using `git clone https://github.com/danb35/freenas-iocage-plex`.  Then create a configuration file called `plex-config` using your preferred text editor.  In its simplest form, the file would look like this:
```
JAIL_IP="192.168.1.75"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
```
These values must be set.  They correspond to:

* JAIL_IP and DEFAULT_GW_IP are the IP addresses of the jail and your router, respectively.
* POOL_PATH is the path for your main data pool's root directory.

Optional configuration values include:

* USE_PLEXPASS - If set to 1, the script will download and install the PlexPass version of Plex Media Server.  Defaults to 0.
* PLEX_CONFIG_PATH - The path to store your Plex metadata and configuration.  Defaults to `$POOL_PATH/plex_data`.

$PLEX_CONFIG_PATH need not exist before running this script; if it doesn't, the script will create it.  The script will also set ownership of that directory to the user/group IDs for Plex Media Server.  If this directory already exists, it **must not** be using Windows permissions.

Note that if the script creates $PLEX_CONFIG_PATH, it will create it as a **directory**, not as a dataset.  This means that it will not appear in, e.g., the Storage section of the FreeNAS GUI, where you could easily see how much space it's using, compression ratio, etc.  If you want these capabilities, you should create the dataset before running the script, and then ensure that $PLEX_CONFIG_PATH is set appropriately.

Once you've prepared the configuration file, run the script by running `./plex-jail.sh`.  It should run for a few minutes and report completion.  You can then add storage to your jail as desired (see [Uncle Fester's Guide](https://www.familybrown.org/dokuwiki/doku.php?id=fester112:jails_plex#configure_a_mount_point) for one example), and log in to configure your media server.

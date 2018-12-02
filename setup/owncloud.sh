#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

# Keep the php5 dependancies for the owncloud upgrades
apt_install \
	dbconfig-common php-pear php-apcu curl libapr1 libtool libcurl4-openssl-dev php-xml-parser memcached 
#	dbconfig-common php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser memcached  \
#	php5-cli php5-sqlite php5-gd php5-imap php5-curl \
#	php5 php5-dev php5-gd php5-fpm php5-memcached

apt-get purge -qq -y owncloud*

apt_install php7.0 php7.0-fpm \
	php7.0-cli php7.0-sqlite php7.0-gd php7.0-imap php7.0-curl php-pear php-apc curl \
        php7.0-dev php7.0-gd memcached php-memcached php7.0-xml php7.0-mbstring php7.0-zip php7.0-apcu php7.0-json php7.0-intl

# Migrate <= v0.10 setups that stored the ownCloud config.php in /usr/local rather than
# in STORAGE_ROOT. Move the file to STORAGE_ROOT.
if [ ! -f ${STORAGE_ROOT}/owncloud/config.php ] \
	&& [ -f /usr/local/lib/owncloud/config/config.php ]; then

	# Move config.php and symlink back into previous location.
	echo "Migrating owncloud/config.php to new location."
	mv /usr/local/lib/owncloud/config/config.php ${STORAGE_ROOT}/owncloud/config.php \
		&& \
	ln -sf ${STORAGE_ROOT}/owncloud/config.php /usr/local/lib/owncloud/config/config.php
fi

SuggestInstallationWithoutNextant() {
	echo
	echo "---------------------------------------------"
	echo " You might want to omit Nextant installation:"
	echo "INSTALL_NEXTANT=no setup/start.sh"
	echo "---------------------------------------------"
}

# Assume Solr was not installed
SOLR_INSTALLED="no"

InstallSolr() {

	# Solr version to download
	local SOLR_VERSION=6.6.2
	echo "Installing solr version ${SOLR_VERSION}"

	# sha1sum get with:
	# curl -s ftp://mirror.hosting90.cz/apache/lucene/solr/6.6.2/solr-6.6.2.tgz | sha1sum
	local SOLR_HASH=e4a772a7770010f85bfce26a39520584a85d5c3f

	local APACHE_FTP_MIRROR=http://archive.apache.org/dist
	#local APACHE_FTP_MIRROR=ftp://mirror.hosting90.cz/apache

	# Also prepare for nextant with solr
	apt_install openjdk-8-jdk tesseract-ocr

	local SOLR_PATH="/usr/local/lib/solr"
	local SOLR_DATA="${STORAGE_ROOT}/solr/data"

	# Before the solr installation begins, first kill running solr instance
	ps faux | grep "solr\.home=${SOLR_PATH}" | awk '{print $2}' | xargs -I {} sh -c 'kill {} || kill -9 {}' &>/dev/null

	wget_verify "${APACHE_FTP_MIRROR}/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz" "${SOLR_HASH}" /tmp/solr.tgz

	if test $? -ne 0; then
		SuggestInstallationWithoutNextant
		exit 1
	fi

	tar xf /tmp/solr.tgz -C /usr/local/lib/
	mv "/usr/local/lib/solr-${SOLR_VERSION}" "${SOLR_PATH}"

	# Listen only on localhost
	if grep -q '<Property name="jetty.host" />' "${SOLR_PATH}/server/etc/jetty-http.xml"; then
		sed -i 's,<Property name="jetty.host" />,<Property name="jetty.host" default="127.0.0.1" />,g' "${SOLR_PATH}/server/etc/jetty-http.xml"
	fi

	# We won't run solr as root, as it is a huge security risk
	useradd solr &>/dev/null

	mkdir -p "${STORAGE_ROOT}/solr/log"

	# Create basic configset for nextant
	if test ! -d ${SOLR_DATA}/nextant; then
		cp -rf ${SOLR_PATH}/server/solr/{configsets/basic_configs,nextant}
		mv ${SOLR_PATH}/server/solr ${SOLR_DATA}
	fi
	ln -sf ${SOLR_DATA} ${SOLR_PATH}/server/solr

	if test -d /etc/systemd && test ! -f ${STORAGE_ROOT}/solr/systemd.service; then
		cat > ${STORAGE_ROOT}/solr/solr.service <<EOF
[Unit]
Description=Apache Solr for Nextcloud's nextant app fulltext indexing
After=syslog.target network.target remote-fs.target nss-lookup.target systemd-journald-dev-log.socket
Before=nginx.service

[Service]
Type=forking
User=solr
Group=solr
WorkingDirectory=${SOLR_PATH}/server
ExecStart=${SOLR_PATH}/bin/solr start -m 256m -Dsolr.log.dir=${STORAGE_ROOT}/solr/log
ExecStop=${SOLR_PATH}/bin/solr stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
		systemctl enable ${STORAGE_ROOT}/solr/solr.service
		systemctl daemon-reload
	else
		cat > ${STORAGE_ROOT}/solr/initd.sh <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          solr
# Required-Start:    \$remote_fs
# Required-Stop:     \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Solr Search Server
# Description:       Solr Search Server for use with Nextant full-text serch for NextCloud.
### END INIT INFO

# Author: jirislav <mail@jkozlovsky.cz>

SOLR_PATH="${SOLR_PATH}"

# -force is only required if running solr as root
start() {
	su solr -c "\${SOLR_PATH}/bin/solr start"
}

stop() {
	su solr -c "\${SOLR_PATH}/bin/solr stop"
}

case "\$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	*)
		echo "Usage: \$0 {start|stop}"
		/bin/false
esac
exit \$?
EOF
		ln -sf ${STORAGE_ROOT}/solr/initd.sh /etc/init.d/solr 
		chmod +x ${STORAGE_ROOT}/solr/initd.sh
		update-rc.d solr defaults
		update-rc.d solr enable
	fi

	chown solr: ${SOLR_PATH} ${SOLR_DATA} -R

	echo "Starting solr to manually create an index for nextant ..."
	su solr -c "${SOLR_PATH}/bin/solr start"

	echo "Creating index for nextant ..."
	su solr -c "${SOLR_PATH}/bin/solr create -c nextant" || echo "nextant core is probably already created #TODO"

	echo "Shutting down solr ..."
	su solr -c "${SOLR_PATH}/bin/solr stop"

	restart_service solr || SuggestInstallationWithoutNextant

	SOLR_INSTALLED="yes"
}

ResetNextAntConfig() {
	# Don't do anything if not installing nextant
	if test ${INSTALL_NEXTANT} = "yes"; then

		# Disable live indexing into mysql because we're not using MySQL ..
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_live', '0')"

		# Index files, files tree & trash 
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_files', '1')"
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_files_tree', '1')"
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_files_trash', '1')"

		# Let nextant take high resources when performing fulltext search
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'resource_level', '4')"

		# Ensure there will be regular cron indexing
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'use_cron', '1')"

		# Timeout at least 1 minute
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'solr_timeout', '60')"

		# Do not force user to configure from the admin module (marking as already configured)..
		sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'configured', '2')"

		# Insert all supported file types
		for file_type in `echo text pdf office image`; do
			sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_files_filters_$file_type', '1')"
		done

		# Do not index only audio for now ..
		for file_type in `echo audio`; do
			sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_appconfig VALUES ('nextant', 'index_files_filters_$file_type', '0')"
		done
	fi
}

# Only set INSTALL_NEXTANT if not set previously (e.g. while running setup/start.sh)
# Note: nextant is a Nextcloud plugin to provide fulltext search even in images
# Note2: Nextant installation is being no longer supported by setup/start.sh script - if you want to install it manually, you can inspire from the code around here ..
if test ! -v INSTALL_NEXTANT; then
	INSTALL_NEXTANT="no"
fi

InstallNextcloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to Nextcloud version $version"
	echo

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.nextcloud.com/server/releases/nextcloud-$version.zip $hash /tmp/nextcloud.zip || exit 1

	# Extract ownCloud/Nextcloud
	unzip -q /tmp/nextcloud.zip -d /usr/local/lib
	mv /usr/local/lib/nextcloud /usr/local/lib/owncloud
	rm -f /tmp/nextcloud.zip

	# The two apps we actually want are not in Nextcloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify https://github.com/nextcloud/contacts/releases/download/v2.1.5/contacts.tar.gz b7460d15f1b78d492ed502d778c0c458d503ba17 /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify https://github.com/nextcloud/calendar/releases/download/v1.6.1/calendar.tar.gz f93a247cbd18bc624f427ba2a967d93ebb941f21 /tmp/calendar.tgz
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz
    
    local SPREED_VERSION=2.0.1
    wget_verify https://github.com/nextcloud/spreed/archive/v${SPREED_VERSION}.tar.gz 6b768afd685e84bef3414c4af734734f47b35298 /tmp/spreed.tgz || exit 1
    tar xf /tmp/spreed.tgz -C /usr/local/lib/owncloud/apps/
    rm /tmp/spreed.tgz
    mv /usr/local/lib/owncloud/apps/spreed-${SPREED_VERSION} /usr/local/lib/owncloud/apps/spreed

	if test ${INSTALL_NEXTANT} = "yes"; then
		#
		# Install nextant to the nextcloud
		# but first solr installation is needed ..
		InstallSolr

		local NEXTANT_VERSION=1.0.8
		local NEXTANT_HASH=ebfbcb028583608e3fa7b9697facc626253dd002

		wget_verify https://github.com/nextcloud/nextant/releases/download/v${NEXTANT_VERSION}/nextant-${NEXTANT_VERSION}.tar.gz "${NEXTANT_HASH}" /tmp/nextant.tgz || exit 1
		tar xf /tmp/nextant.tgz -C /usr/local/lib/owncloud/apps/
		rm /tmp/nextant.tgz
	elif systemctl list-unit-files | grep -q solr.service; then
		# Stop & disable solr service so that our resources are more available
		systemctl stop solr.service &>/dev/null
		systemctl disable solr.service &>/dev/null
	fi


	# Fix weird permissions.
	chmod 750 -R /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf ${STORAGE_ROOT}/owncloud/config.php /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# ${STORAGE_ROOT}/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data.www-data ${STORAGE_ROOT}/owncloud /usr/local/lib/owncloud

	# If this isn't a new installation, immediately run the upgrade script.
	# Then check for success (0=ok and 3=no upgrade needed, both are success).
	if [ -e ${STORAGE_ROOT}/owncloud/owncloud.db ]; then
		# ownCloud 8.1.1 broke upgrades. It may fail on the first attempt, but
		# that can be OK.
		sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi
	fi
}

# We only install ownCloud intermediate versions to be able to seemlesly upgrade to Nextcloud
InstallOwncloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to OwnCloud version $version"
	echo

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.owncloud.org/community/owncloud-$version.tar.bz2 $hash /tmp/owncloud.tar.bz2 || exit 1


	# Extract ownCloud
	tar xjf /tmp/owncloud.tar.bz2 -C /usr/local/lib
	rm -f /tmp/owncloud.tar.bz2

	# The two apps we actually want are not in Nextcloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify https://github.com/owncloud/contacts/releases/download/v1.4.0.0/contacts.tar.gz c1c22d29699456a45db447281682e8bc3f10e3e7 /tmp/contacts.tgz || exit 1
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify https://github.com/nextcloud/calendar/releases/download/v1.4.0/calendar.tar.gz c84f3170efca2a99ea6254de34b0af3cb0b3a821 /tmp/calendar.tgz || exit 1
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz

	# Fix weird permissions.
	chmod 750 /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf ${STORAGE_ROOT}/owncloud/config.php /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# ${STORAGE_ROOT}/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data.www-data ${STORAGE_ROOT}/owncloud /usr/local/lib/owncloud

	# If this isn't a new installation, immediately run the upgrade script.
	# Then check for success (0=ok and 3=no upgrade needed, both are success).
	if [ -e ${STORAGE_ROOT}/owncloud/owncloud.db ]; then
		# ownCloud 8.1.1 broke upgrades. It may fail on the first attempt, but
		# that can be OK.
		sudo -u www-data php5 /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php5 /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php5 /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi
	fi
}

owncloud_ver=13.0.6
owncloud_hash=33e41f476f0e2be5dc7cdb9d496673d9647aa3d6

# Check if Nextcloud dir exist, and check if version matches owncloud_ver (if either doesn't - install/upgrade)
if [ ! -d /usr/local/lib/owncloud/ ] \
        || ! grep -q $owncloud_ver /usr/local/lib/owncloud/version.php; then

	# Stop php-fpm if running. If theyre not running (which happens on a previously failed install), dont bail.
	service php7.0-fpm stop &> /dev/null || /bin/true
	# service php5-fpm stop &> /dev/null || /bin/true

	# Backup the existing ownCloud/Nextcloud.
	# Create a backup directory to store the current installation and database to
	BACKUP_DIRECTORY=${STORAGE_ROOT}/owncloud-backup/`date +"%Y-%m-%d-%T"`
	mkdir -p "$BACKUP_DIRECTORY"
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "upgrading ownCloud/Nextcloud to $owncloud_flavor $owncloud_ver (backing up existing installation, configuration and database to directory to $BACKUP_DIRECTORY..."
		cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	fi
	if [ -e /home/user-data/owncloud/owncloud.db ]; then
		cp /home/user-data/owncloud/owncloud.db $BACKUP_DIRECTORY
        fi
        if [ -e /home/user-data/owncloud/config.php ]; then
                cp /home/user-data/owncloud/config.php $BACKUP_DIRECTORY
        fi

	# We only need to check if we do upgrades when owncloud/Nextcloud was previously installed
	if [ -e /usr/local/lib/owncloud/version.php ]; then
		if grep -q "OC_VersionString = '8\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running 8.1.x, upgrading to 8.2.11 first"
			InstallOwncloud 8.2.11 e4794938fc2f15a095018ba9d6ee18b53f6f299c
		fi

		# If we are upgrading from 8.2.x we should go to 9.0 first. Owncloud doesn't support skipping minor versions
		if grep -q "OC_VersionString = '8\.2\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running version 8.2.x, upgrading to 9.0.11 first"

			# We need to disable memcached. The upgrade and install fails
			# with memcached
			CONFIG_TEMP=$(/bin/mktemp)
			php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP ${STORAGE_ROOT}/owncloud/config.php;
			<?php
				include("${STORAGE_ROOT}/owncloud/config.php");

				\$CONFIG['memcache.local'] = '\OC\Memcache\APCu';

				echo "<?php\n\\\$CONFIG = ";
				var_export(\$CONFIG);
				echo ";";
			?>
EOF
			chown www-data.www-data ${STORAGE_ROOT}/owncloud/config.php

			# We can now install owncloud 9.0.11
			InstallOwncloud 9.0.11 fc8bad8a62179089bc58c406b28997fb0329337b

			# The owncloud 9 migration doesn't migrate calendars and contacts
			# The option to migrate these are removed in 9.1
			# So the migrations should be done when we have 9.0 installed
			sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:migrate-addressbooks
			# The following migration has to be done for each owncloud user
			for directory in ${STORAGE_ROOT}/owncloud/*@*/ ; do
				username=$(basename "${directory}")
				sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:migrate-calendar $username
			done
			sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:sync-birthday-calendar
		fi

        
		# If we are upgrading from 9.0.x we should go to 9.1 first.
		if grep -q "OC_VersionString = '9\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.0.x, upgrading to ownCloud 9.1.7 first"
			InstallOwncloud 9.1.7 1307d997d0b23dc42742d315b3e2f11423a9c808
		fi

		# Newer ownCloud 9.1.x versions cannot be upgraded to Nextcloud 10 and have to be
		# upgraded to Nextcloud 11 straight away, see:
		# https://github.com/nextcloud/server/issues/2203
		# However, for some reason, upgrading to the latest Nextcloud 11.0.7 doesn't
		# work either. Therefore, we're upgrading to Nextcloud 11.0.0 in the interim.
		# This should not be a problem since we're upgrading to the latest Nextcloud 12
		# in the next step.
		if grep -q "OC_VersionString = '9\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.1.x, upgrading to Nextcloud 11.0.0 first"
			InstallNextcloud 11.0.0 e8c9ebe72a4a76c047080de94743c5c11735e72e
		fi

		# If we are upgrading from 10.0.x we should go to Nextcloud 11.0 first.
		if grep -q "OC_VersionString = '10\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running Nextcloud 10.0.x, upgrading to Nextcloud 11.0.7 first"
			InstallNextcloud 11.0.7 f936ddcb2ae3dbb66ee4926eb8b2ebbddc3facbe
		fi

		# If we are upgrading from Nextcloud 11 we should go to Nextcloud 12 first.
		if grep -q "OC_VersionString = '11\." /usr/local/lib/owncloud/version.php; then
			echo "We are running Nextcloud 11, upgrading to Nextcloud 12.0.5 first"
			InstallNextcloud 12.0.5 d25afbac977a4e331f5e38df50aed0844498ca86
		fi
	fi

	InstallNextcloud $owncloud_ver $owncloud_hash
fi

# ### Configuring Nextcloud

# Setup Nextcloud if the Nextcloud database does not yet exist. Running setup when
# the database does exist wipes the database and user data.
if [ ! -f ${STORAGE_ROOT}/owncloud/owncloud.db ]; then
	# Create user data directory
	mkdir -p ${STORAGE_ROOT}/owncloud

	# Create an initial configuration file.
	instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
	cat > ${STORAGE_ROOT}/owncloud/config.php <<EOF
<?php
\$CONFIG = array (
  'datadirectory' => '${STORAGE_ROOT}/owncloud',

  'instanceid' => '$instanceid',

  'forcessl' => true, # if unset/false, Nextcloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
  'overwrite.cli.url' => '/cloud',
  'user_backends' => array(
    array(
      'class'=>'OC_User_IMAP',
      'arguments'=>array('{127.0.0.1:993/imap/ssl/novalidate-cert}')
    )
  ),
  'memcache.local' => '\OC\Memcache\APCu',
  'mail_smtpmode' => 'sendmail',
  'mail_smtpsecure' => '',
  'mail_smtpauthtype' => 'LOGIN',
  'mail_smtpauth' => false,
  'mail_smtphost' => '',
  'mail_smtpport' => '',
  'mail_smtpname' => '',
  'mail_smtppassword' => '',
  'mail_from_address' => 'owncloud',
);
?>
EOF

	# Create an auto-configuration file to fill in database settings
	# when the install script is run. Make an administrator account
	# here or else the install can't finish.
	adminpassword=$(dd if=/dev/urandom bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
	cat > /usr/local/lib/owncloud/config/autoconfig.php <<EOF
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory' => '${STORAGE_ROOT}/owncloud',
  'dbtype' => 'sqlite3',

  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of Nextcloud
  'adminlogin'    => 'root',
  'adminpass'     => '$adminpassword',
);
?>
EOF

	# Set permissions
	chown -R www-data.www-data ${STORAGE_ROOT}/owncloud /usr/local/lib/owncloud

	# Execute Nextcloud's setup step, which creates the Nextcloud sqlite database.
	# It also wipes it if it exists. And it updates config.php with database
	# settings and deletes the autoconfig.php file.
	(cd /usr/local/lib/owncloud; sudo -u www-data php /usr/local/lib/owncloud/index.php;)
fi

ResetNextAntConfig

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# * mail_domain' needs to be set every time we run the setup. Making sure we are setting 
#   the correct domain name if the domain is being change from the previous setup.
# Use PHP to read the settings file, modify it, and write out the new settings array.
TIMEZONE=$(cat /etc/timezone)
CONFIG_TEMP=$(/bin/mktemp)
php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP ${STORAGE_ROOT}/owncloud/config.php
<?php
include("${STORAGE_ROOT}/owncloud/config.php");

\$CONFIG['trusted_domains'] = array('$PRIMARY_HOSTNAME');

\$CONFIG['memcache.local'] = '\OC\Memcache\APCu';
\$CONFIG['overwrite.cli.url'] = '/cloud';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches our master administrator address

\$CONFIG['logtimezone'] = '$TIMEZONE';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

\$CONFIG['mail_domain'] = '$PRIMARY_HOSTNAME';

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF
chown www-data.www-data ${STORAGE_ROOT}/owncloud/config.php

# Enable/disable apps. Note that this must be done after the Nextcloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows Nextcloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable calendar
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable spreed

# Don't do anything if not installing nextant
if test ${INSTALL_NEXTANT} = "yes"; then
	hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable nextant

	# Do not hide output - these tests are pretty nice 0:) 
	sudo -u www-data php /usr/local/lib/owncloud/occ nextant:test http://127.0.0.1:8983/solr/ nextant --save
	
	# Start indexing on the background
	hide_output sudo -u www-data php /usr/local/lib/owncloud/occ nextant:index --background --unlock
fi

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/7.0/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set Nextcloud recommended opcache settings
tools/editconf.py /etc/php/7.0/cli/conf.d/10-opcache.ini -c ';' \
	opcache.enable=1 \
	opcache.enable_cli=1 \
	opcache.interned_strings_buffer=8 \
	opcache.max_accelerated_files=10000 \
	opcache.memory_consumption=128 \
	opcache.save_comments=1 \
	opcache.revalidate_freq=1

# Configure the path environment for php-fpm
tools/editconf.py /etc/php/7.0/fpm/pool.d/www.conf -c ';' \
        env[PATH]=/usr/local/bin:/usr/bin:/bin

# If apc is explicitly disabled we need to enable it
if grep -q apc.enabled=0 /etc/php/7.0/mods-available/apcu.ini; then
	tools/editconf.py /etc/php/7.0/mods-available/apcu.ini -c ';' \
		apc.enabled=1
fi

# Set up a cron job for Nextcloud.
cat > /etc/cron.hourly/mailinabox-owncloud << EOF;
#!/bin/bash
# Mail-in-a-Box
sudo -u www-data php -f /usr/local/lib/owncloud/cron.php
EOF
chmod +x /etc/cron.hourly/mailinabox-owncloud

# There's nothing much of interest that a user could do as an admin for Nextcloud,
# and there's a lot they could mess up, so we don't make any users admins of Nextcloud.
# But if we wanted to, we would do this:
# ```
# for user in $(tools/mail.py user admins); do
#	 sqlite3 ${STORAGE_ROOT}/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
restart_service php7.0-fpm

if test "$SOLR_INSTALLED" = "yes"; then
	restart_service solr
fi

#!/usr/bin/env bash

#MYSQL_PW_FILE="~/.pw_mysql_root"
MYSQL_PW_FILE="/home/marc/.pw_mysql_root"
APACHE_LOG_DIR="/var/log/apache2"
EMAIL="mgreyling@gmail.com"

[ $(id -u) == "0" ] || { echo "Need to run script as root"; exit 1; }

(( $# < 1 )) && { echo "Domain as arg1 missing!"; exit 1; } || { echo "Domain: ""$1"; DOMAIN="$1"; }

DIR="/var/www/html/$DOMAIN"
DBNAME=$(echo ${DOMAIN%%.*} | tr -d -c '[[:alnum:]]')
U=$DBNAME
P="$DBNAME""pw"

#read -s -p "Domain:" DOMAIN

#IP=$(hostname -I | awk '{print $1}')
for i in `hostname -I`; do [[ $i =~ "127"* || $i =~ "::"* ]] && continue || { IP="$i"; break; }; done
echo "IP: $IP"

#ping -c1 "$DOMAIN" 2>/dev/null || echo uh oh
#RESOLVED=$(ping -c1 "$DOMAIN" 2>/dev/null); echo $?
#echo $RESOLVED | awk '{print $2}'

## Initial checks

echo -n "Checking if domain $DOMAIN resolves to this host's IP $IP ..."
_IP=""
if which getent >/dev/null; then
	_IP=$(getent hosts $DOMAIN | awk '{ print $1 ; exit }')
elif which dig >/dev/null; then
	_IP=$(dig +short $DOMAIN | awk '{ print ; exit }')
else
	echo -e "\nNeither 'dig' nor 'getent' available on this system. Exiting." 
	exit 2
fi

echo ""
if [[ ! -z _$IP && "$_IP" == "$IP" ]]; then
	echo "Yay, this host's IP, $IP matches the domain name resolution $_IP"
else
	echo "Uh oh! This host's IP, $IP does not match the domain name resolution ${_IP}."
	echo "Does the DNS entry for $DOMAIN exist?"
fi

#.pw_mysql_root
if [[ ! -f "$MYSQL_PW_FILE" ]]; then
	echo "Make sure a file $MYSQL_PW_FILE exists, containing the MySQL root password and with perms 400."
	exit 64
else
	#MYSQL_ROOT_PW="$(cat $MYSQL_PW_FILE | xargs)"
	MYSQL_PWD="$(cat $MYSQL_PW_FILE | xargs)"
fi

## Doing install

###if false; then # TEMP

echo -n "Now installing Wordpress ... "
cd ~
if wget -c http://wordpress.org/latest.tar.gz; then
	mv latest.tar.gz wordpress__latest.tar.gz 
else
	echo -e "Problems downloading tarball. Exiting."
	exit 4
fi

if [ -d "$DIR" ] && find "$DIR" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
	echo -e "\nDirectory $DIR already exists and is not empty. Exiting."
	exit 8
elif mkdir -p "$DIR"; then
	echo -e "\nSuccess creating dir $DIR ."
else
	echo -e "\nFailed to create directory $DIR. Exiting."
	exit 16
fi

if cd "$DIR" && tar zxf ~/wordpress__latest.tar.gz; then
	if cd wordpress/ && mv * .. && cd .. && rmdir wordpress && cd .. ; then
		echo "Wordpress unpacked to dir $DIR ."
	else
		echo "Problems unpacking Wordpress tarball. Exiting."
		exit 32
	fi
fi

echo -n "Now setting permissions (could take a while) ... "
cd $DIR
#chown www-data:www-data -R * # Let Apache be owner
chown www-data:www-data -R . # Let Apache be owner
find . -type d -exec sudo chmod 755 {} \;  # Change directory permissions rwxr-xr-x
find . -type f -exec sudo chmod 644 {} \;  # Change file permissions rw-r--r--

echo Exit code now: $?

[[ $MYSQL_PWD ]] || { echo "MySQL password variable 'MYSQL_PWD' not set. "; exit 512; }

echo -n "Now setting up DB $DBNAME ... "
echo -n "with USERNAME $U and PW $p ... "

#mysql -uroot -p${MYSQL_ROOT_PW} -e "CREATE DATABASE ${DBNAME};"
MYSQL_PWD=$MYSQL_PWD mysql -uroot -e "CREATE DATABASE ${DBNAME};"
#mysql -uroot -p${MYSQL_ROOT_PW} -e "CREATE USER ${U}@localhost IDENTIFIED BY '${P}';"
MYSQL_PWD=$MYSQL_PWD mysql -uroot -e "CREATE USER ${U}@localhost IDENTIFIED BY '${P}';"
#mysql -uroot -p${MYSQL_ROOT_PW} -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${U}'@'localhost';"
MYSQL_PWD=$MYSQL_PWD mysql -uroot -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${U}'@'localhost';"
#mysql -uroot -p${MYSQL_ROOT_PW} -e "FLUSH PRIVILEGES;"
MYSQL_PWD=$MYSQL_PWD mysql -uroot -e "FLUSH PRIVILEGES;"
#mysql -uroot -p${MYSQL_ROOT_PW} -e "ALTER DATABASE ${DBNAME} CHARACTER SET utf8 COLLATE utf8_unicode_ci;" # ensure utf8 charset
MYSQL_PWD=$MYSQL_PWD mysql -uroot -e "ALTER DATABASE ${DBNAME} CHARACTER SET utf8 COLLATE utf8_unicode_ci;" # ensure utf8 charset

echo "done."

if mv wp-config-sample.php wp-config.php; then
	sed -i "s/database_name_here/${DBNAME}/g" wp-config.php
	sed -i "s/username_here/${U}/g" wp-config.php
	sed -i "s/password_here/${P}/g" wp-config.php

	if ! egrep -q "define.+'FORCE_SSL_ADMIN'.+true" wp-config.php ; then
		echo -n "Forcing SSL for admin ... "
		echo "define('FORCE_SSL_ADMIN', true);" >> wp-config.php && echo "done."
	fi

else
	echo "Error creating wp-config.php. Exiting."
	exit 64
fi

###fi # TEMP

#F="/etc/apache2/sites-available/05-${DOMAIN}.conf"
SITE="05-${DOMAIN}.conf"
F="/etc/apache2/sites-available/$SITE"
if [[ -f "$F" ]]; then
	echo "$F already exits"
else
	echo "Creating apache2 vhost conf file $F ... "
	read -r -d '' CONF <<EOF
<VirtualHost *:80>
        ServerName      ${DOMAIN}
        ServerAdmin     adm@neuesziel.de
        DocumentRoot    ${DIR}
        SetEnvIf        Request_URI "^/favicon.ico" dontlog

        ErrorLog ${APACHE_LOG_DIR}/${DOMAIN}-error.log
        CustomLog ${APACHE_LOG_DIR}/${DOMAIN}-access.log combined env=!dontlog

        <Directory ${DIR}>
                RewriteEngine On
                RewriteCond %{REQUEST_FILENAME} !-f
                RewriteCond %{REQUEST_FILENAME} !-d
                RewriteRule . index.php
        </Directory>

        # hide .git directory
        <DirectoryMatch /\.git/>
                Order deny,allow
                Deny from all
        </DirectoryMatch>

</VirtualHost>
EOF
	echo "${CONF}" | tee -a "$F"
	a2ensite "$SITE"
fi

# SSL
if certbot certificates 2>/dev/null | egrep -q 'Domains:.*'${DOMAIN}; then 
	echo "SSL certificate for $DOMAIN already exists."
elif ! which certbot; then
	echo "Need to install certbot. Exiting."
	exit 128
else
	echo "Getting SSL certificate ... "
	#certbot certonly -n --agree-tos --no-eff-email --email $EMAIL --redirect -d $DOMAIN --apache
	#if certbot -n --agree-tos --no-eff-email --email $EMAIL --redirect -d $DOMAIN --apache; then
	if certbot -n --agree-tos --no-eff-email --email $EMAIL --no-redirect -d $DOMAIN --apache; then
		service apache2 graceful
	fi
fi

echo "Try accessing new WP site at https://"$DOMAIN

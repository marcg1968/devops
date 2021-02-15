#!/usr/bin/env bash

# Script to set up a single Wordpress installation based on specified domain
#
URL="https://raw.githubusercontent.com/marcg1968/devops/master/wp-single-site.sh"
URL="https://raw.githubusercontent.com/marcg1968/devops/dev-01/wp-single-site.sh"
# run the script by entering
# curl -s "$URL" | bash
# OR
# wget -qO - "$URL" | bash

checkroot() {
    if [ "$(id -u)" -eq 0 ]; then
        # user is root and good to go
	echo "User has root privilege"
    else
    	# assume sudo command exists
	echo "User "$(id -un)" (id="$(id -u)") does NOT have root privilege ..."
	
	# when running via curl piping
	if [[ "$0" == "bash" ]]; then
            # download script and run with root rights
	    exec curl -sSL "$URL" | sudo bash "$@"
        else
	    # when running by calling local bash script
            exec sudo bash "$0" "$@"
	fi
	
	# Now exiting
	exit $?
    fi	
}

checkroot

USR=""
while [ -z "$USR" ]; do
    read -p "Enter the main user (not root): " username </dev/tty
    username="$(echo $username | tr -d '[:space:]')"
	[ -z "$username" ] && { echo must be non-zero; continue; }

    USR="$username"
done

echo $USR
MYSQL_PW_FILE="/home/"${USR}"/.pw_mysql_root"
echo ${MYSQL_PW_FILE}

[ -e "${MYSQL_PW_FILE}" ] || {
    echo ;
    echo "# Please create a password file as follows:";
    echo "touch ${MYSQL_PW_FILE}";
    echo "chmod 400 ${MYSQL_PW_FILE}";
    echo "# with a single line containing the MySQL root password.";
    echo ;
    exit 2;
}


read -p "Enter email address: "  EMAIL </dev/tty

APACHE_LOG_DIR="/var/log/apache2"
[ -d $APACHE_LOG_DIR ] || APACHE_LOG_DIR=""

while [ -z $APACHE_LOG_DIR ]; do
    read -p "Enter full path to Apache log directory: " apache_log </dev/tty
    apache_log="$(echo $apache_log | tr -d '[:space:]')"
    #[ -z "$apache_log" -o ! -d "$apache_log" ] && { echo "invalid entry"; continue; }
    [ -z "$apache_log" ] && { echo "Invalid entry"; continue; }
    [ -d "$apache_log" ] || { echo "Directory does not exist"; continue; }
    echo "Setting APACHE_LOG_DIR=$apache_log"
    APACHE_LOG_DIR="$apache_log"
done

DOMAIN=""
while [ -z "$DOMAIN" ]; do
    read -p "Enter domain: " domain </dev/tty
    domain="$(echo $domain | tr -d '[:space:]')"
	[ -z "$domain" ] && { echo must be of non-zero length; continue; }
    

    # checking IP domain name resolution
    KNOWN_IP=""
    if which getent >/dev/null; then
	    KNOWN_IP=$(getent hosts $domain | awk '{ print $1 }')
        [[ "$KNOWN_IP" =~ "127"* ]] && KNOWN_IP=""
    fi
    if which dig >/dev/null && [ -z $KNOWN_IP ] ; then
        KNOWN_IP=$(dig +short $domain)
    else
        echo -e "\nNeither 'dig' nor 'getent' available on this system. Exiting." 
        exit 8
    fi
    [ -z "$KNOWN_IP" ] && { echo "IP for this domain could not be determined. Is the domain correct?"; continue; }

    echo KNOWN_IP $KNOWN_IP
    echo "Using domain '"$domain"'"
    DOMAIN="$domain"
done

DIR="/var/www/html/$DOMAIN"
DBNAME=$(echo ${DOMAIN%%.*} | tr -d -c '[[:alnum:]]')
U=$DBNAME
P="$DBNAME""pw"

#for i in `hostname -I`; do [[ $i =~ "127"* || $i =~ "::"* ]] && continue || { IP="$i"; break; }; done
#echo "IP: $IP"


for i in `hostname -I`; do 
    [[ $i =~ "127"* || $i =~ "::"* ]] && continue
    # try this IP
    [ "$i" = "$KNOWN_IP" ] && IP="$i"
done

echo "External IP determined to be $IP"

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



exit 0







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

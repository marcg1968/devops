#!/usr/bin/env bash

# Script to set up a single Wordpress installation based on specified domain
#
URL="https://raw.githubusercontent.com/marcg1968/devops/master/wp-single-site.sh"
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

check() {
    local MISSING="1"
    if which getent >/dev/null; then
	    MISSING=""
    elif which dig >/dev/null; then
        MISSING=""
    fi
    [ -z "$MISSING" ] && echo "Check passed: getent or dig available on system." || { 
        echo "Check failed: neither 'dig' nor 'getent' available on this system. Exiting."; exit 32; 
    }
}

checkroot

check

USR=""
while [ -z "$USR" ]; do
    read -p "Enter the main user (not root): " username </dev/tty
    username="$(echo $username | tr -d '[:space:]')"
	[ -z "$username" ] && { echo must be non-zero; continue; }

    USR="$username"
done

echo "Welcome, ${USR}. Now for a few checks and prompts ..."
MYSQL_PW_FILE="/home/"${USR}"/.pw_mysql_root"
#echo ${MYSQL_PW_FILE}

[ -e "${MYSQL_PW_FILE}" ] || {
    echo ;
    echo "For this script to access the MySQL database, you need to create a secure password file in your home directory.";
    echo "# Please create a password file as follows:";
    echo "touch ${MYSQL_PW_FILE}";
    echo "chmod 400 ${MYSQL_PW_FILE}";
    echo "# with a single line containing the MySQL root password.";
    echo ;
    exit 2;
}
MYSQL_PWD=$(<${MYSQL_PW_FILE})

sleep 1
echo 
echo "A valid email address is required for the LetsEncrypt SSL certificate."
read -p "Please enter email address: "  EMAIL </dev/tty

sleep1
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
echo
while [ -z "$DOMAIN" ]; do
    read -p "Enter domain: " domain </dev/tty
    domain="$(echo $domain | tr -d '[:space:]')"
	[ -z "$domain" ] && { echo must be of non-zero length; continue; }
    
    sleep 1
    # checking IP domain name resolution
    KNOWN_IP=""
    if which getent >/dev/null; then
	    KNOWN_IP=$(getent hosts $domain | awk '{ print $1 }')
        [[ "$KNOWN_IP" =~ "127"* ]] && KNOWN_IP=""
    fi
    if [ -z "$KNOWN_IP" ] && which dig >/dev/null; then
        KNOWN_IP=$(dig +short $domain)
    fi

    [ -z "$KNOWN_IP" ] && { echo "IP for this domain could not be determined. Is the domain correct?"; continue; }

    echo KNOWN_IP $KNOWN_IP
    echo "Using domain '"$domain"'"
    DOMAIN="$domain"
done

IP=""
# now need to check if KNOWN_IP for DOMAIN matches our external IP
for i in `hostname -I`; do 
    [[ $i =~ "127"* || $i =~ "::"* ]] && continue
    # try this IP
    echo "trying external IP $i ... "
    [ "$i" = "$KNOWN_IP" ] && IP="$i"
done

[ -z "$IP" ] && { echo "No external IP matches the IP ($KNOWN_IP) of the domain. Exiting."; exit 64; }
echo "Good to go - this host's IP, $IP matches the domain name resolution $KNOWN_IP"

DIR="/var/www/html/$DOMAIN"
DBNAME=$(echo ${DOMAIN%%.*} | tr -d -c '[[:alnum:]]')
U=$DBNAME"_"$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)
#P="$DBNAME""pw"
P=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

## Doing install

echo
sleep 1
echo -n "Now installing Wordpress ... "
cd ~

## if false; then # TEMP

NOW=`date +%s`
AGE=""
TGZ="wordpress__latest.tar.gz"
# stat -c%Y ~/wordpress__latest.tar.gz
[ -f "$TGZ" ] && AGE=$(($NOW-`stat -c%Y $TGZ`))
if [[ -z "$AGE" || "$AGE" > "86400" ]]; then
    if wget -c http://wordpress.org/latest.tar.gz; then
	    mv latest.tar.gz wordpress__latest.tar.gz 
    else
	    echo -e "Problems downloading tarball. Exiting."
    	exit 128
    fi
fi

if [ -d "$DIR" ] && find "$DIR" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
	echo -e "\nDirectory $DIR already exists and is not empty. Exiting."
	exit 128
elif mkdir -p "$DIR"; then
	echo -e "\nSuccess creating dir $DIR ."
else
	echo -e "\nFailed to create directory $DIR. Exiting."
	exit 128
fi

#if cd "$DIR" && tar zxf ~/wordpress__latest.tar.gz; then
cd "$DIR" || exit 128
tar zxf ~/wordpress__latest.tar.gz && echo "Wordpress unpacked" || { echo "Problems unpacking Wordpress tarball. Exiting."; exit 128; }
cd wordpress/ || exit 128
mv * .. || exit 128
cd .. || exit 128
rmdir wordpress || exit 128
cd .. && echo -e "Unpacked Wordpress installation moved to dir\n\t $DIR" || exit 128
echo
sleep 1

## fi # TEMP

### NOTE: permissions should be tightened up later - this is for the initial wordpress setup
echo -n "Now setting permissions on directory $DIR (could take a while) ... "
cd $DIR
#chown www-data:www-data -R * # Let Apache be owner
chown www-data:www-data -R . # Let Apache be owner
find . -type d -exec sudo chmod 755 {} \;  # Change directory permissions rwxr-xr-x
find . -type f -exec sudo chmod 644 {} \;  # Change file permissions rw-r--r--

echo "Exit code now: "$?
echo "(0 - indicates success)"
echo 
sleep 1

[[ $MYSQL_PWD ]] || { echo "MySQL password variable 'MYSQL_PWD' not set. "; exit 512; }

echo -n "Now setting up MySQL DB $DBNAME ... "
echo -n "with USERNAME $U ... "

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
echo
echo "+---------------------------------------------------------------------------------------+"
echo -e "For DB $DBNAME\nUSER=${U}\nPASSWORD=${P}" >> ~/.wordpress_db_credentials_${DBNAME}
sudo chown $USR ~/.wordpress_db_credentials_${DBNAME}
sudo chmod 400 ~/.wordpress_db_credentials_${DBNAME}
echo "   Credentials saved to file ${HOME}/.wordpress_db_credentials_${DBNAME}"
echo "+---------------------------------------------------------------------------------------+"
echo 

if mv wp-config-sample.php wp-config.php; then
	sed -i "s/database_name_here/${DBNAME}/g" wp-config.php
	sed -i "s/username_here/${U}/g" wp-config.php
	sed -i "s/password_here/${P}/g" wp-config.php

	if ! egrep -q "define.+'FORCE_SSL_ADMIN'.+true" wp-config.php ; then
		echo -n "Forcing SSL for admin in WP config ... "
		echo "define('FORCE_SSL_ADMIN', true);" >> wp-config.php && echo "done."
	fi

else
	echo "Error creating wp-config.php. Exiting."
	exit 64
fi
echo 
sleep 1

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
echo 
sleep 1

echo "Setting up LetsEncrypt SSL certificates ..."
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
		echo 
		echo -n "Now gracefully reloading Apache ... "
		service apache2 graceful
		echo 
	fi
fi
sleep 1
echo "NOTE: now the database needs to be imported and WP configuration complete."
echo 
echo "Try accessing new WP site at https://"$DOMAIN
echo 

exit 0



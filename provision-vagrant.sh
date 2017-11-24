#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

readonly SHARED_DIR='/vagrant'
readonly WWW_DIR='/var/www/html'
readonly WP_DIR='public_html'
readonly PROFILES=("$HOME/.bash_profile" "$HOME/.bashrc")
readonly DBNAME=vagrant
readonly DBUSER=vagrant
readonly DBPASSWD=vagrantP@ss
readonly WP_URL='https://wordpress.org/'
readonly WP_PKG='latest.tar.gz'
readonly DEPENDENCIES=(
    sysv-rc-conf
    apache2
    php libapache2-mod-php php-mysql
    php-mbstring php-mcrypt php-curl php-gd php-xml
)

install_dependencies() {
    echo '# Installing dependencies...   '
    sudo apt-get install -y -- "${DEPENDENCIES[@]}"
}

update_apt() {
    echo '# Updating...                  '
    sudo apt-get update -y
    sudo apt-get upgrade -y
}

setup_mysql() {
    echo '# Setting up mysql...          '
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $DBPASSWD"
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $DBPASSWD"
    sudo apt-get -y install mysql-server 
    mysql -uroot -p$DBPASSWD -e "CREATE DATABASE $DBNAME"
    mysql -uroot -p$DBPASSWD -e "grant all privileges on $DBNAME.* to '$DBUSER'@'localhost' identified by '$DBPASSWD'"
    sudo sysv-rc-conf mysqld on
}

setup_wordpress() {
    echo '# Setting up WordPress...      '
    echo '# Referenced by https://help.ubuntu.com/lts/serverguide/wordpress.html      '
    if [[ -d "${WWW_DIR}/${WP_DIR}" ]]; then
        return
    fi

    # Download & move to public directory
    echo '# Downloading WordPress Stable, see ${WP_URL}'
    cd ${WWW_DIR}
    sudo curl -L -O ${WP_URL}${WP_PKG}
    sudo tar -xvf ${WP_PKG}
    sudo mv wordpress ${WP_DIR}
    sudo rm ${WP_PKG}

    echo "# Configuring WordPress Stable..."

    # Setup privilege
    cd ${WWW_DIR}
    sudo chown -R www-data:www-data ${WP_DIR}
    sudo chmod -R 755 ${WP_DIR}

    # Modify conf files 
    cd ${WP_DIR}
    sudo mv wp-config-sample.php wp-config.php

    sudo sed wp-config.php -e "
         /^define('DB_NAME'/c     define('DB_NAME', '$DBNAME');
         /^define('DB_USER'/c     define('DB_USER', '$DBUSER');
         /^define('DB_PASSWORD'/c define('DB_PASSWORD', '$DBPASSWD');
    " -i

    curl https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/secret

    sudo sed wp-config.php -e "
     /^define('AUTH_KEY'/r /tmp/secret
     /^define('SECURE_AUTH_KEY'/d
     /^define('LOGGED_IN_KEY'/d
     /^define('NONCE_KEY'/d
     /^define('AUTH_SALT'/d
     /^define('SECURE_AUTH_SALT'/d
     /^define('LOGGED_IN_SALT'/d
     /^define('NONCE_SALT'/d
     " -i

    rm /tmp/secret
}

setup_apache() {
    echo '# Setting up apache...         '

    # Setup vhosts file
    if [[ ! -d "/etc/apache2/sites-available/wordpress.conf" ]]; then
        sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/wordpress.conf
    fi
    echo "        DocumentRoot $WWW_DIR/$WP_DIR" > /tmp/public_dir
    sudo sed /etc/apache2/sites-available/wordpress.conf -e "
     /DocumentRoot/r /tmp/public_dir
    " -i
    rm /tmp/public_dir

    sudo sysv-rc-conf apache2 on
    sudo a2enmod rewrite
    sudo a2dissite 000-default
    sudo a2ensite wordpress
    sudo systemctl restart apache2
}

main() {
    echo '# Start setting up...          '

    #update_apt
    install_dependencies
    setup_mysql
    setup_wordpress
    setup_apache

    echo '# WordPress is all set up.     '
    echo '# Visit http://192.168.33.10   '
}

main

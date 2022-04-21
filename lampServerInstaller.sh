#!/bin/bash

# Author: Sam Lampe
# Course: System Automation and Scripting​
# Term: Spring 2022
# Date: 2/28/2022
# Description: Installs and configures Apache, MariaDB,
# Nextcloud and Samba, gathers system information and
# collects it in a Samba share, and adds users from
# a file.  

##### CONSTANTS
IFS="," # separator for csv files
DATE=$(date +%y-%m-%d) # date for log archive name
CURRENT_DIR=$(pwd) # current dir to return to if cd is used

##### VARIABLES
file="" # used to test if services are configured
firstname="" # stores first name of added users
lastname="" # stores last name of added users
password="" # stores password of added users
group="" # stores group name of added users
shouldimport="" # helps determine if user should be added or not

##### FUNCTIONS

# Installs Apache and configures it for Nextcloud.
installApache() {

    ##### Install Apache
    # I found how to install Apache here:
    # https://docs.nextcloud.com/server/latest/admin_manual/installation/example_centos.html
    echo "Installing Apache 2.4..."
    dnf install -y httpd #install apache
    
    
    ##### Verify File
    # I found how to used the test command here:
    # https://linuxize.com/post/bash-check-if-file-exists/
    file=/etc/httpd/conf/httpd.conf
    if test -f $file; then
        echo "Apache install verified."
    else
        echo "Error. Appache not verified."
    fi
    
    
    ##### Configure Apache (for Nextcloud)
    # I found how to configure Apache for NC here:
    # https://docs.nextcloud.com/server/latest/admin_manual/installation/source_installation.html
    echo "Configuring Apache..."

    # Add virtual host for nextcloud to apache
    cat > /etc/httpd/conf.d/nextcloud.conf << _EOF_
<VirtualHost *:80>
  DocumentRoot /var/www/html/nextcloud/
  ServerName  your.server.com

  <Directory /var/www/html/nextcloud/>
    Require all granted
    AllowOverride All
    Options FollowSymLinks MultiViews

    <IfModule mod_dav.c>
      Dav off
    </IfModule>

  </Directory>
</VirtualHost>
_EOF_
    
    echo "Starting Apache..."
    systemctl enable httpd.service # run on startup
    systemctl start httpd.service # start apache
    
    echo "Restarting Apache..."
    service httpd restart
    
    echo "Apache configuraiton and install complete."
    echo ""
}

# Installs and configures Samba, and creates a network share.
installSamba() {

    ##### Install Samba
    # I found how to install/configure/create users/shares here:
    # https://www.tecmint.com/install-samba4-on-centos-7-for-file-sharing-on-windows/
    echo "Installing Samba 4.14..."
    sudo yum install samba samba-client samba-common cifs-utils -y
    
    
    ##### Verify File
    echo "Verifying installation..."
    file=/etc/samba/smb.conf
    if test -f $file; then
        echo "Samba install verified."
    else
        echo "Error. Samba not verified."
    fi
    
    
    ##### Create Samba config w/ share, overwrite default config
    echo "Configuring Samba..."
    
    # firewall config
    firewall-cmd --permanent --zone=public --add-service=samba # configure firewall
    echo "Restarting firewall..."
    firewall-cmd --reload
    
    # backup samaba config (smb.conf) file
    cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
    
    # make a file for the shares, assign permisions
    mkdir -p /srv/samba/anonymous
    chmod -R 7777 /srv/samba/anonymous
    chown -R nobody:nobody /srv/samba/anonymous
    chcon -t samba_share_t /srv/samba/anonymous
    
    # overwrite config file
    cat > /etc/samba/smb.conf << _EOF_
[global]
    workgroup = WORKGROUP
    netbios name = centos
    security = user
[Anonymous]
    comment = Anonymous File Server Share
    path = /srv/samba/anonymous
    browsable =yes
    writable = yes
    guest ok = yes
    read only = no
    force user = nobody
_EOF_
    #testparm # test config
    
    # start samba on startup, start now
    systemctl enable smb.service
    systemctl enable nmb.service
    echo "Starting samba..."
    systemctl start smb.service
    systemctl start nmb.service
    
    echo "Samba configuration and install complete."
    echo ""
}

# Installs and configures MariaDB, prepared for Nextcloud.
installMaria() {

    ##### Install MariaDB
    echo "Installing MariaDB 10.5.15..."

    # I found how to install MariaDB here:
    # https://mariadb.org/download/?t=repo-config&d=CentOS+8+%28x86_64%29&v=10.5&r_m=gigenet
    cat > /etc/yum.repos.d/MariaDB.repo << _EOF_
# MariaDB 10.5 CentOS repository list - created 2022-03-02 18:40 UTC
# https://mariadb.org/download/
[mariadb]
name = MariaDB
baseurl = https://mirrors.gigenet.com/mariadb/yum/10.5/centos8-amd64
module_hotfixes=1
gpgkey=https://mirrors.gigenet.com/mariadb/yum/RPM-GPG-KEY-MariaDB
gpgcheck=1
_EOF_
    sudo dnf install MariaDB-server -y
    sudo systemctl enable mariadb
    echo "Starting MariaDB..."
    sudo systemctl start mariadb


    ##### Verify File
    echo "Verifying installation..."
    file=/etc/my.cnf.d/server.cnf
    if test -f $file; then
        echo "MariaDB install verified."
    else
        echo "Error. MariaDB not verified."
    fi


    ##### Configure DB
    echo "Configuring MariaDB..."

    # Remove anonymous users, set up password for root
    # I found how to remove anon users & add root pass using mysql_secure_installation here:
    # https://docs.nextcloud.com/server/latest/admin_manual/installation/example_centos.html

    # I found how to pipe automatic responses to a command here:
    # https://www.baeldung.com/linux/bash-interactive-prompts
    printf "\nn\nY\nPassword01\nPassword01\nY\nY\nY\nY\n" | mysql_secure_installation

    # The printf command automatically answers prompts with the following:
    #	 _ | n | Y | Password01 | Password01 | Y | Y | Y | Y
    # This takes care of setting up the root password and deleting anonymous users.

    # Create database/user/pass for Nextcloud to use
    # I found how to run MySQL commands from bash here:
    # https://geekdudes.wordpress.com/2020/07/16/linux-bash-script-for-creating-and-configuring-maria-database/
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud" # create db
    sudo mysql -e "CREATE USER IF NOT EXISTS 'nextcloud_user'@'localhost' IDENTIFIED BY 'Password01'" # create user for nextcloud
    sudo mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* to 'nextcloud_user'@'localhost'"

    echo "MariaDB install and configuration complete."
    echo ""
}

# Installs and configures Nextcloud.
installNextcloud() {

    # I used the CentOS example from Nextcloud for the basic structure:
    # https://docs.nextcloud.com/server/latest/admin_manual/installation/example_centos.html

    ##### Install Dependencies
    echo "Installing dependencies..."
    dnf install -y epel-release yum-utils unzip curl wget bash-completion policycoreutils-python-utils mlocate bzip2


    ##### Install PHP
    # install Remi repo, needed for PHP
    echo "Installing Remi repo..."
    dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y
    dnf install yum-utils -y
    echo "Resetting php module..."
    dnf module reset php -y
    dnf module install php:remi-7.4 -y
    
    # install PHP modules
    echo "Installing PHP modules..."
    dnf install -y php php-gd php-mbstring php-intl php-pecl-apcu php-mysqlnd php-opcache php-json php-zip php-process


    ##### Install Nextcloud Proper
    # install/enable Redis
    echo "Installing Redis..."
    dnf install -y redis
    systemctl enable redis.service
    echo "Starting Redis..."
    systemctl start redis.service
    
    # I found how to download a Nextcloud archive here:
    # https://www.linuxbabe.com/ubuntu/install-nextcloud-ubuntu-20-04-apache-lamp-stack

    # I found how to wget to a specific directory here:
    # https://www.tecmint.com/wget-download-file-to-specific-directory/
    echo "Installing Nextcloud..."
    sudo wget https://download.nextcloud.com/server/releases/nextcloud-23.0.2.zip -P /var/www/html

    # I found how to extract to a specific folder here:
    # https://askubuntu.com/questions/520546/how-to-extract-a-zip-file-to-a-specific-folder
    echo "Extracting Nextcloud..."
    sudo unzip /var/www/html/nextcloud-23.0.2.zip -d /var/www/html

    mkdir /var/www/html/nextcloud/data
    chown -R apache:apache /var/www/html/nextcloud/data
    
    echo "Restarting Apache..."
    systemctl restart httpd.service
    
    # add rule for apache to firewall
    firewall-cmd --zone=public --add-service=http --permanent
    echo "Restarting firewall..."
    firewall-cmd --reload
    
    # SELinux configuration
    echo "Configuring SELinux..."
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/data(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/config(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/apps(/.*)?'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.htaccess'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.user.ini'
    semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/3rdparty/aws/aws-sdk-php/src/data/logs(/.*)?'

    restorecon -R '/var/www/html/nextcloud/'

    setsebool -P httpd_can_network_connect on

    # Install Nextcloud with occ
    # I found how to install Nextcloud from bash here:
    # https://docs.nextcloud.com/server/latest/admin_manual/installation/command_line_installation.html
    echo "Installing Nextcloud server..."
    sudo chown -R apache:apache /var/www/html/nextcloud/
    cd /var/www/html/nextcloud/
    sudo -u apache php occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud_user" --database-pass "Password01" --admin-user "admin" --admin-pass "password"
    # using creds from MariaDB install

    echo "Restarting Apache..."
    systemctl restart httpd.service


    ##### Verify File
    echo "Verifying installation..."
    file=/var/www/html/nextcloud/config/config.php
    if test -f $file; then
        echo "Nextcloud install verified."
    else
        echo "Error. Nextcloud not verified."
    fi

    echo "Nextcloud install and configuration finished."
    echo ""
}

# Imports users from the project_users.csv file, creates groups, and
# removes users whose last names begin with C or M.
importUsers() {
    echo "Importing users..."

    ##### Create Groups
    echo "Adding employees group..."
    groupadd "employees"
    echo "Adding supervisors group..."
    groupadd "supervisors"
    echo "Adding contractors group..."
    groupadd "contractors"


    ##### Create Users
    # Basic structure came from importDemo on Talon
    while read firstname lastname password group shouldimport; do

        if [ $shouldimport == "import" ]
        then
            useradd -c "$firstname $lastname" -G $group -m -p $(openssl passwd -1 $password) "$firstname-$lastname"
            echo "Imported $firstname $lastname to $group group."
        else
            echo "User not imported."
        fi

    done < ./project_users.csv


    ##### Delete M and C Users
    while read firstname lastname password group shouldimport; do

        # I found how to get the first letter of a str from here:
        # https://reactgo.com/bash-get-first-character-of-string/
        if [[ ${lastname:0:1} == "C" || ${lastname:0:1} == "M" ]]
        then
            userdel -r "$firstname-$lastname"
            echo "Deleted user $firstname-$lastname."
        fi

    done < ./project_users.csv


    echo "User creation complete."
    echo ""
}

# Cleans the /tmp directory, mounts a samba share, and saves log files
# and other system info to the share
collectInfo() {
    ##### Delete tmp files
    # I found how to delte all files from a dir here:
    # https://linoxide.com/how-to-remove-all-files-from-directory-in-linux/
    echo "Deleting files from /tmp..."
    rm -rf /tmp/{*,.*}


    ##### Mount Samba share
    echo "Mounting Samba share..."
    # I found how to use mount.cifs on a share from the 1st answer here:
    # https://askubuntu.com/questions/725440/mount-a-samba-network-drive-from-terminal-without-hardcoding-a-password

    mkdir /mnt/sambashare
    mount -t cifs //127.0.0.1/Anonymous /mnt/sambashare -o sec=none
    # I found the sec=none option from the mount.cifs man page


    ##### Collect Info
    echo "Collecting system information..."
    echo "Collecting running services..."
    # I found how to list all running services here:
    # https://www.tecmint.com/list-all-running-services-under-systemd-in-linux/
    systemctl --type=service >> /mnt/sambashare/running-services.txt

    echo "Collecting services in /etc/services..."
    cat /etc/services >> /mnt/sambashare/etc-services.txt

    echo "Collecting results of top command..."
    # I found how to run the top command here:
    # https://linuxhint.com/top-batch-mode-linux/
    top -b -n 5 >> /mnt/sambashare/top.txt

    echo "Collecting system log files..."
    # I found how to compress files here:
    # https://www.freecodecamp.org/news/how-to-compress-files-in-linux-with-tar-command/
    tar -czvf /mnt/sambashare/Logs_${DATE}.tar.gz /var/log/* 


    ##### Collect Info of my choice, x3
    echo "Collecting system users..."
    cat /etc/passwd >> /mnt/sambashare/users.txt

    echo "Collecting cron jobs for root..."
    crontab -l >> /mnt/sambashare/cron-jobs.txt

    echo "Checking storage space..."
    # I found how to use df here:
    # https://phoenixnap.com/kb/linux-check-disk-space
    df >> /mnt/sambashare/storage-space.txt

    echo "Finished collecting info."
    echo ""
}

# Download Hunt the Wumpus, a classic game I re-made in
# bash several weeks ago.
# This is the one extra thing of my choosing.
huntTheWumpus() {

    echo "Downloading 'Hunt the Wumpus'..."
    cd $CURRENT_DIR
    wget https://github.com/sam8457/HuntTheWumpus/archive/refs/heads/main.zip
    echo "Extracting..."
    unzip main.zip
    chmod 777 ./HuntTheWumpus-main/huntTheWumpus.sh
    echo "Type './HuntTheWumpus-main/huntTheWumpus.sh' to play."
    echo ""

}

##### MAIN

# Only run script if root
if [ $(id -u) = "0" ]
then

    echo ""
    installApache # required for nextcloud
    installSamba # required for collecting info
    installMaria # required for nextcloud
    installNextcloud
    importUsers
    collectInfo
    huntTheWumpus

else
    echo "Please run as super user."
fi

echo "Goodbye."

exit 0
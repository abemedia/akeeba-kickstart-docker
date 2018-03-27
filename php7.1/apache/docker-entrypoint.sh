#!/bin/bash

set -e

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
        if [ -n "$MYSQL_PORT_3306_TCP" ]; then
                if [ -z "$JOOMLA_DB_HOST" ]; then
                        JOOMLA_DB_HOST='mysql'
                else
                        echo >&2 "warning: both JOOMLA_DB_HOST and MYSQL_PORT_3306_TCP found"
                        echo >&2 "  Connecting to JOOMLA_DB_HOST ($JOOMLA_DB_HOST)"
                        echo >&2 "  instead of the linked mysql container"
                fi
        fi

        if [ -z "$JOOMLA_DB_HOST" ]; then
                echo >&2 "error: missing JOOMLA_DB_HOST and MYSQL_PORT_3306_TCP environment variables"
                echo >&2 "  Did you forget to --link some_mysql_container:mysql or set an external db"
                echo >&2 "  with -e JOOMLA_DB_HOST=hostname:port?"
                exit 1
        fi

        if [ -z "$JOOMLA_BACKUP_URL" ]; then
                echo >&2 "error: missing JOOMLA_BACKUP_URL environment variable"
                exit 1
        fi

        # If the DB user is 'root' then use the MySQL root password env var
        : ${JOOMLA_DB_USER:=root}
        if [ "$JOOMLA_DB_USER" = 'root' ]; then
                : ${JOOMLA_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
        fi
        : ${JOOMLA_DB_NAME:=joomla}

        if [ -z "$JOOMLA_DB_PASSWORD" ] && [ "$JOOMLA_DB_PASSWORD_ALLOW_EMPTY" != 'yes' ]; then
                echo >&2 "error: missing required JOOMLA_DB_PASSWORD environment variable"
                echo >&2 "  Did you forget to -e JOOMLA_DB_PASSWORD=... ?"
                echo >&2
                echo >&2 "  (Also of interest might be JOOMLA_DB_USER and JOOMLA_DB_NAME.)"
                exit 1
        fi

        if ! [ -e index.php -a \( -e libraries/cms/version/version.php -o -e libraries/src/Version.php \) ]; then
                echo >&2 "Joomla not found in $(pwd) - copying now..."

                if [ "$(ls -A)" ]; then
                        echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
                        ( set -x; ls -A; sleep 10 )
                fi

                JOOMLA_BACKUP_FILE=$(echo ${JOOMLA_BACKUP_URL##*/} | cut -d? -f1)

                # download backup archive
                STATUS=$(curl -sL -o $JOOMLA_BACKUP_FILE -w '%{http_code}' -SL "$JOOMLA_BACKUP_URL")
                if [ ! "$STATUS" -lt "400" ]; then
                        echo >&2 "error: got HTTP status $STATUS when trying to access $JOOMLA_BACKUP_URL"
                        exit 1
                fi

                # extract backup archive
                [ ! -z "$AKEEBA_PASSWORD" ] && FLAGS="$FLAGS --password=\"$AKEEBA_PASSWORD\""
                [ "$AKEEBA_PERMISSIONS" = true ] && FLAGS="$FLAGS --permissions"
                php /usr/src/kickstart.php $JOOMLA_BACKUP_FILE $FLAGS
                chown -R www-data:www-data /var/www/html
                rm -rf $JOOMLA_BACKUP_FILE

                # set db config defaults
                if [ -f './installation/sql/databases.ini' ]; then
                        sed -i -e "/dbhost =/ s/= .*/= \"$JOOMLA_DB_HOST\"/" ./installation/sql/databases.ini
                        sed -i -e "/dbuser =/ s/= .*/= \"$JOOMLA_DB_USER\"/" ./installation/sql/databases.ini
                        sed -i -e "/dbpass =/ s/= .*/= \"$JOOMLA_DB_PASSWORD\"/" ./installation/sql/databases.ini
                        sed -i -e "/dbname =/ s/= .*/= \"$JOOMLA_DB_NAME\"/" ./installation/sql/databases.ini
                fi

                if [ ! -e .htaccess ]; then
                        # NOTE: The "Indexes" option is disabled in the php:apache base image so remove it as we enable .htaccess
                        sed -r 's/^(Options -Indexes.*)$/#\1/' htaccess.txt > .htaccess
                        chown www-data:www-data .htaccess
                fi

                echo >&2 "Complete! Joomla has been successfully copied to $(pwd)"
        fi

        # Ensure the MySQL Database is created
        php /makedb.php "$JOOMLA_DB_HOST" "$JOOMLA_DB_USER" "$JOOMLA_DB_PASSWORD" "$JOOMLA_DB_NAME"

        echo >&2 "========================================================================"
        echo >&2
        echo >&2 "This server is now configured to run Joomla!"
        echo >&2 "You will need the following database information to install Joomla:"
        echo >&2 "Host Name: $JOOMLA_DB_HOST"
        echo >&2 "Database Name: $JOOMLA_DB_NAME"
        echo >&2 "Database Username: $JOOMLA_DB_USER"
        echo >&2 "Database Password: $JOOMLA_DB_PASSWORD"
        echo >&2
        echo >&2 "========================================================================"
fi

exec "$@"

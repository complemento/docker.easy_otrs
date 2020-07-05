FROM ubuntu:16.04
MAINTAINER Complemento <https://www.complemento.net.br>

# Definitions
ARG BUILD_OTRS_VERSION=6.0.27

ENV OTRS_VERSION=${BUILD_OTRS_VERSION}

RUN apt-get update && \
    apt-get install -y supervisor \
    apt-utils \
    libterm-readline-perl-perl && \
    apt-get install -y locales && \
    locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN apt-get install -y apache2 git bash-completion cron sendmail

# CREATE OTRS USER
RUN useradd -d /opt/otrs -c 'OTRS user' otrs && \
    usermod -a -G www-data otrs && \
    usermod -a -G otrs www-data

RUN mkdir /opt/src && \
    cd /opt/src/ && \
    chown otrs:www-data /opt/src && \
    su -c "git clone -b rel-$(echo $OTRS_VERSION | sed --expression='s/\./_/g') \
    --single-branch https://github.com/OTRS/otrs.git" -s /bin/bash otrs

RUN sed -i -e "s/6.0.x git/${OTRS_VERSION}/g" /opt/src/otrs/RELEASE

COPY link.pl /opt/src/

RUN chmod 755 /opt/src/link.pl && \
    mkdir /opt/otrs && \
    chown otrs:www-data /opt/otrs

# perl modules
RUN apt-get install -y  libarchive-zip-perl \
                        libcrypt-eksblowfish-perl \
                        libcrypt-ssleay-perl \
                        libtimedate-perl \
                        libdatetime-perl \
                        libdbi-perl \
                        libdbd-mysql-perl \
                        libdbd-odbc-perl \
                        libdbd-pg-perl \
                        libencode-hanextra-perl \
                        libio-socket-ssl-perl \
                        libjson-xs-perl \
                        libmail-imapclient-perl \
                        libio-socket-ssl-perl \
                        libauthen-sasl-perl \
                        libauthen-ntlm-perl \
                        libapache2-mod-perl2 \
                        libnet-dns-perl \
                        libnet-ldap-perl \
                        libtemplate-perl \
                        libtemplate-perl \
                        libtext-csv-xs-perl \
                        libxml-libxml-perl \
                        libxml-libxslt-perl \
                        libxml-parser-perl \
                        libyaml-libyaml-perl \
                        libmoo-perl \
                        libnamespace-clean-perl


RUN /opt/src/otrs/bin/otrs.SetPermissions.pl --web-group=www-data

RUN ln -s /opt/src/otrs/scripts/apache2-httpd.include.conf /etc/apache2/sites-available/otrs.conf && \
    a2ensite otrs && \
    a2dismod mpm_event && \
    a2enmod mpm_prefork && \
    a2enmod headers

################## EASY OTRS DOCKER #############
# Install database
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y install mysql-server
COPY z_my_otrs.cnf /etc/mysql/mysql.conf.d/

# See Bug https://stackoverflow.com/questions/9083408/fatal-error-cant-open-and-lock-privilege-tables-table-mysql-host-doesnt-ex
RUN chown -R mysql:mysql /var/lib/mysql && \
    /etc/init.d/mysql start && \
    while ! mysqladmin ping --silent; do sleep 1; done && \
    mysqladmin -u root password ligero && \
    mysql -u root -pligero -e "GRANT ALL PRIVILEGES ON *.* TO otrs@localhost IDENTIFIED BY 'ligero'; FLUSH PRIVILEGES;" && \
    mysql -u otrs -pligero -e "CREATE DATABASE otrs DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;" && \
    mysql -u otrs -pligero otrs < /opt/src/otrs/scripts/database/otrs-schema.mysql.sql && \
    mysql -u otrs -pligero otrs < /opt/src/otrs/scripts/database/otrs-initial_insert.mysql.sql && \
    mysql -u otrs -pligero otrs < /opt/src/otrs/scripts/database/otrs-schema-post.mysql.sql

#################################################
# Supervisor
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Setup a cron for checking when OTRS is already installed, then start otrs Cron
COPY daemonstarter.sh /opt/src/
RUN chmod +x /opt/src/daemonstarter.sh
RUN echo "* * * * * /opt/src/daemonstarter.sh" | crontab -

COPY otrs.sh /opt/src/
RUN chmod 755 /opt/src/otrs.sh

EXPOSE 80

CMD ["/opt/src/otrs.sh"]

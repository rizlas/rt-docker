FROM perl:latest as builder

ENV RT="rt-5.0.2"
ENV RT_SHA256="df915ae809277564d9b8a7192ced2517cf6bed6c0301786b69562c0ea9dd9e86"

# use cpanm for dependencies
ENV RT_FIX_DEPS_CMD="cpanm --no-man-pages"

# Create RT user
RUN groupadd -g 1000 rt && useradd -u 1000 -g 1000 -Ms /bin/bash -d /opt/rt5 rt

# Install required packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
  && apt-get -q -y install --no-install-recommends \
  ca-certificates wget gnupg graphviz libssl1.1 zlib1g \
  libgd3 libexpat1 libpq5 w3m elinks links html2text lynx openssl libgd-dev

# Download and extract RT
RUN mkdir -p /src \
  # download and extract RT
  && wget -O /src/${RT}.tar.gz -nv https://download.bestpractical.com/pub/rt/release/${RT}.tar.gz \
  && echo "${RT_SHA256} /src/${RT}.tar.gz" | sha256sum -c - \
  && tar -C /src -xzf /src/${RT}.tar.gz

# Configure RT
RUN cd /src/${RT} \
  # configure with all plugins and with the newly created user
  && ./configure --with-db-type=Pg --enable-gpg --enable-gd --enable-graphviz --enable-smime --with-web-user=rt --with-web-group=rt --with-rt-group=rt --with-bin-owner=rt --with-libs-owner=rt

# Install dependencies
RUN make -C /src/${RT} fixdeps \
  && make -C /src/${RT} testdeps \
  && make -C /src/${RT} install \
  && cpanm --install RT::Extension::MergeUsers \
  && cpanm --install RT::Extension::TerminalTheme

FROM perl:slim

# Install required packages
# we use busybox-static here for the busybox crond which works
# without systemd
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
  && apt-get -q -y install --no-install-recommends \
  supervisor msmtp ca-certificates getmail wget curl gnupg graphviz libssl1.1 zlib1g \
  libgd3 libexpat1 libpq5 w3m elinks links html2text lynx openssl busybox-static \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Create RT user
RUN useradd -u 1000 -Ms /bin/bash -d /opt/rt5 rt

# copy all needed stuff from the builder image
COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5
COPY --from=builder /opt/rt5 /opt/rt5

# run a final dependency check if we copied all 
RUN perl /opt/rt5/sbin/rt-test-dependencies --with-pg --with-fastcgi --with-gpg --with-graphviz --with-gd

# supervisord config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN mkdir -p /var/log/supervisor/ \
  && chown rt:rt /var/log/supervisor/ \
  && mkdir -p /var/run/supervisord \
  && chown rt:rt /var/run/supervisord

# cron config and install busybox symlink for crond
RUN mkdir -p /var/spool/cron/crontabs \
  && ln -fs /bin/busybox /usr/sbin/crond

# msmtp config
RUN mkdir /msmtp \
  && chown rt:rt /msmtp \
  # also fake sendmail for cronjobs
  && ln -s /usr/bin/msmtp /usr/sbin/sendmail

# getmail
RUN mkdir -p /getmail \
  && chown rt:rt /getmail

# gpg
RUN mkdir -p /opt/rt5/var/data/gpg \
  && chown rt:rt /opt/rt5/var/data/gpg

# smime
RUN mkdir -p /opt/rt5/var/data/smime \
  && chown rt:rt /opt/rt5/var/data/smime

# shredder dir
RUN mkdir -p /opt/rt5/var/data/RT-Shredder \
  && chown rt:rt /opt/rt5/var/data/RT-Shredder

# update PATH
ENV PATH="${PATH}:/opt/rt5/sbin:/opt/rt5/bin"

EXPOSE 9000

USER rt
WORKDIR /opt/rt5/

CMD [ "/usr/bin/supervisord" ]

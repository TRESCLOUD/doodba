###############################################################################
# Base image
###############################################################################
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim-bookworm AS base

EXPOSE 8069 8072

ARG TARGETARCH
ARG PYTHON_VERSION
ARG GEOIP_UPDATER_VERSION=6.0.0
ARG WKHTMLTOPDF_VERSION=0.12.6.1
ARG WKHTMLTOPDF_AMD64_CHECKSUM='98ba0d157b50d36f23bd0dedf4c0aa28c7b0c50fcdcdc54aa5b6bbba81a3941d'
ARG WKHTMLTOPDF_ARM64_CHECKSUM="b6606157b27c13e044d0abbe670301f88de4e1782afca4f9c06a5817f3e03a9c"
ARG WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}-3/wkhtmltox_${WKHTMLTOPDF_VERSION}-3.bookworm_${TARGETARCH}.deb"

ARG LAST_SYSTEM_UID=499
ARG LAST_SYSTEM_GID=499
ARG FIRST_UID=500
ARG FIRST_GID=500

ENV DB_FILTER=.* \
    DEPTH_DEFAULT=1 \
    DEPTH_MERGE=100 \
    EMAIL=https://hub.docker.com/r/tecnativa/odoo \
    GEOIP_ACCOUNT_ID="" \
    GEOIP_LICENSE_KEY="" \
    GIT_AUTHOR_NAME=docker-odoo \
    INITIAL_LANG="" \
    LC_ALL=C.UTF-8 \
    LIST_DB=false \
    NODE_PATH=/usr/local/lib/node_modules:/usr/lib/node_modules \
    OPENERP_SERVER=/opt/odoo/auto/odoo.conf \
    PATH="/home/odoo/.local/bin:$PATH" \
    PIP_NO_CACHE_DIR=0 \
    DEBUGPY_ARGS="--listen 0.0.0.0:6899 --wait-for-client" \
    DEBUGPY_ENABLE=0 \
    PUDB_RDB_HOST=0.0.0.0 \
    PUDB_RDB_PORT=6899 \
    PYTHONOPTIMIZE="" \
    UNACCENT=true \
    WAIT_DB=true \
    WDB_NO_BROWSER_AUTO_OPEN=True \
    WDB_SOCKET_SERVER=wdb \
    WDB_WEB_PORT=1984 \
    WDB_WEB_SERVER=localhost

###############################################################################
# System setup
###############################################################################
RUN echo "LAST_SYSTEM_UID=$LAST_SYSTEM_UID\nLAST_SYSTEM_GID=$LAST_SYSTEM_GID\nFIRST_UID=$FIRST_UID\nFIRST_GID=$FIRST_GID" >> /etc/adduser.conf \
 && echo "SYS_UID_MAX   $LAST_SYSTEM_UID\nSYS_GID_MAX   $LAST_SYSTEM_GID" >> /etc/login.defs \
 && sed -i -E "s/^UID_MIN\s+[0-9]+.*/UID_MIN   $FIRST_UID/;s/^GID_MIN\s+[0-9]+.*/GID_MIN   $FIRST_GID/" /etc/login.defs \
 && useradd --system -u $LAST_SYSTEM_UID -s /usr/sbin/nologin -d / systemd-network \
 && apt-get -qq update \
 && apt-get install -yqq --no-install-recommends curl

###############################################################################
# wkhtmltopdf + system deps
###############################################################################
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        WKHTMLTOPDF_CHECKSUM=$WKHTMLTOPDF_ARM64_CHECKSUM; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        WKHTMLTOPDF_CHECKSUM=$WKHTMLTOPDF_AMD64_CHECKSUM; \
    else \
        echo "Unsupported architecture: $TARGETARCH" >&2; exit 1; \
    fi \
 && curl -SLo wkhtmltox.deb ${WKHTMLTOPDF_URL} \
 && echo "${WKHTMLTOPDF_CHECKSUM} wkhtmltox.deb" | sha256sum -c - \
 && apt-get install -yqq --no-install-recommends \
        ./wkhtmltox.deb \
        chromium \
        ffmpeg \
        fonts-liberation2 \
        gettext \
        git \
        gnupg2 \
        locales-all \
        nano \
        npm \
        openssh-client \
        telnet \
        vim \
 && rm -f wkhtmltox.deb

###############################################################################
# GeoIP
###############################################################################
RUN echo 'deb https://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main' \
        > /etc/apt/sources.list.d/postgresql.list \
 && curl -SL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
 && apt-get update \
 && curl -L -o geoipupdate.deb \
        https://github.com/maxmind/geoipupdate/releases/download/v${GEOIP_UPDATER_VERSION}/geoipupdate_${GEOIP_UPDATER_VERSION}_linux_${TARGETARCH}.deb \
 && dpkg -i geoipupdate.deb \
 && rm geoipupdate.deb \
 && apt-get autopurge -yqq \
 && rm -rf /var/lib/apt/lists/* /tmp/*

###############################################################################
# Doodba core
###############################################################################
WORKDIR /opt/odoo

COPY bin/* /usr/local/bin/
COPY lib/doodbalib /usr/local/lib/python${PYTHON_VERSION}/site-packages/doodbalib
COPY build.d common/build.d
COPY conf.d common/conf.d
COPY entrypoint.d common/entrypoint.d

RUN rm -f /opt/odoo/common/conf.d/60-geoip-lt17.conf \
 && mv /opt/odoo/common/conf.d/60-geoip-ge17.conf \
       /opt/odoo/common/conf.d/60-geoip.conf \
 && mkdir -p auto/addons auto/geoip custom/src/private \
 && ln /usr/local/bin/direxec common/entrypoint \
 && ln /usr/local/bin/direxec common/build \
 && chmod -R a+rx common/entrypoint* common/build* /usr/local/bin \
 && chmod -R a+rX /usr/local/lib/python${PYTHON_VERSION}/site-packages/doodbalib

###############################################################################
# QA venv
###############################################################################
COPY qa /qa
RUN python -m venv --system-site-packages /qa/venv \
 && . /qa/venv/bin/activate \
 && pip install click coverage \
 && deactivate \
 && mkdir -p /qa/artifacts

###############################################################################
# Odoo deps
###############################################################################
ARG ODOO_SOURCE=OCA/OCB
ARG ODOO_VERSION=18.0
ENV ODOO_VERSION=${ODOO_VERSION}

RUN build_deps="build-essential libpq-dev libxml2-dev libxslt-dev" \
 && apt-get update \
 && apt-get install -yqq --no-install-recommends $build_deps \
 && curl -o requirements.txt \
      https://raw.githubusercontent.com/${ODOO_SOURCE}/${ODOO_VERSION}/requirements.txt \
 && pip install --upgrade setuptools \
 && pip install -r requirements.txt \
        debugpy \
        wdb \
 && python -m compileall -q /usr/local/lib/python${PYTHON_VERSION} || true \
 && apt-get purge -yqq $build_deps \
 && apt-get autopurge -yqq \
 && rm -rf /var/lib/apt/lists/* /tmp/*

###############################################################################
# ONBUILD image
###############################################################################
FROM base AS onbuild

ONBUILD ARG UID=1000
ONBUILD ARG GID=1000

ONBUILD RUN groupadd -g $GID odoo -o \
 && useradd -l -md /home/odoo -s /bin/false -u $UID -g $GID odoo \
 && mkdir -p /var/lib/odoo \
 && chown -R odoo:odoo /var/lib/odoo /qa/artifacts

ONBUILD ENTRYPOINT ["/opt/odoo/common/entrypoint"]
ONBUILD CMD ["/usr/local/bin/odoo"]

ONBUILD COPY --chown=root:odoo ./custom /opt/odoo/custom
ONBUILD RUN /opt/odoo/common/build && sync
ONBUILD VOLUME ["/var/lib/odoo"]
ONBUILD USER odoo

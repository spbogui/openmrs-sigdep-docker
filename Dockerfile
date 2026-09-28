# syntax=docker/dockerfile:1
# ============================================================================
#  Image SIGDEP 3.x  —  spbogui/sigdep:<version>
#  OpenMRS 2.x (WAR local) + modules SIGDEP sur Tomcat 9 / JRE 8 (Alpine)
#
#  Ce que l'image NE contient PAS (volontairement, pour rester légère) :
#    - le dump de la base  -> chargé par le conteneur MySQL (db/init/)
#    - mysql-client        -> l'attente de la base se fait par test TCP (nc)
# ============================================================================
ARG TOMCAT_IMAGE=tomcat:9.0-jre8-temurin
ARG JRE_IMAGE=eclipse-temurin:8-jre-alpine

# ---------------------------------------------------------------------------
# Étape 1 : récupération de Tomcat 9 (binaire Java pur, portable)
# ---------------------------------------------------------------------------
FROM ${TOMCAT_IMAGE} AS tomcat

# ---------------------------------------------------------------------------
# Étape 2 : préparation (nettoyage Tomcat + WAR pré-décompressé)
# ---------------------------------------------------------------------------
FROM alpine:3.20 AS builder
COPY --from=tomcat /usr/local/tomcat /usr/local/tomcat
COPY wars/openmrs.war /tmp/openmrs.war
COPY docker/ROOT/ /usr/local/tomcat/webapps/ROOT/
COPY docker/entrypoint.sh /tmp/entrypoint.sh
RUN set -eux; \
    cd /usr/local/tomcat; \
    # applications, docs et bibliothèques natives (glibc) inutiles
    rm -rf webapps.dist native-jni-lib bin/*.bat bin/*.tar.gz \
           RELEASE-NOTES RUNNING.txt BUILDING.txt CONTRIBUTING.md README.md; \
    # pas de journal d'accès HTTP (économise le disque sur les sites)
    sed -i '/AccessLogValve/,/\/>/d' conf/server.xml; \
    # UTF-8 + caractères tolérés dans les URL (UI legacy OpenMRS)
    sed -i 's#<Connector port="8080" protocol="HTTP/1.1"#<Connector port="8080" protocol="HTTP/1.1" URIEncoding="UTF-8" relaxedQueryChars="[]|{}^\&\#x5c;\&\#x60;\&quot;\&lt;\&gt;" relaxedPathChars="[]|"#' conf/server.xml; \
    # WAR pré-décompressé : démarrage plus rapide, pas de double copie
    mkdir -p webapps/openmrs; \
    unzip -q /tmp/openmrs.war -d webapps/openmrs; \
    rm -f /tmp/openmrs.war; \
    # fin de ligne Unix (au cas où le dépôt a été extrait sous Windows en CRLF)
    sed -i 's/\r$//' /tmp/entrypoint.sh; chmod 755 /tmp/entrypoint.sh

# ---------------------------------------------------------------------------
# Étape 3 : image finale
# ---------------------------------------------------------------------------
FROM ${JRE_IMAGE}

ARG VERSION=3.0.0
LABEL org.opencontainers.image.title="SIGDEP" \
      org.opencontainers.image.description="SIGDEP 3.x (OpenMRS 2.x) - Tomcat 9 / JRE 8" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="spbogui"

ENV CATALINA_HOME=/usr/local/tomcat \
    PATH=/usr/local/tomcat/bin:$PATH \
    OPENMRS_DATA_DIR=/openmrs/data \
    SIGDEP_VERSION=${VERSION} \
    TZ=Africa/Abidjan \
    LANG=C.UTF-8

RUN set -eux; \
    apk add --no-cache su-exec tzdata fontconfig ttf-dejavu; \
    addgroup -S -g 1000 openmrs; \
    adduser -S -D -H -u 1000 -G openmrs -h /openmrs openmrs; \
    mkdir -p /openmrs/data /opt/sigdep/modules; \
    chown -R openmrs:openmrs /openmrs

COPY --from=builder --chown=openmrs:openmrs /usr/local/tomcat /usr/local/tomcat
COPY --chown=openmrs:openmrs modules/*.omod /opt/sigdep/modules/
COPY --from=builder /tmp/entrypoint.sh /usr/local/bin/entrypoint.sh

VOLUME ["/openmrs/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=15m --retries=5 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/openmrs/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["catalina.sh", "run"]

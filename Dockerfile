# ONLYOFFICE DocumentServer with Mobile Editing Unlocked
# Based on official ONLYOFFICE DocumentServer

FROM onlyoffice/documentserver:9.2.1

LABEL maintainer="Your Name"
LABEL description="ONLYOFFICE DocumentServer with mobile editing enabled"

# Copy the modified web-apps directory
COPY ./web-apps /var/www/onlyoffice/documentserver/web-apps

# Set proper permissions
RUN chown -R ds:ds /var/www/onlyoffice/documentserver/web-apps

# Expose ports
EXPOSE 80 443

# Use the default CMD from the base image
CMD ["/app/ds/run-document-server.sh"]

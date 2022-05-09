# Specify the eXist-db image with preloaded data app as a base image
FROM ghcr.io/biblia-arabica/biblia-arabica-data:latest

# Exist autodeploy directory
ENV autodeploy=/exist/autodeploy/

# Grab remote .xar files and put them in autodeploy
ADD http://exist-db.org:8098/exist/apps/public-repo/public/shared-resources-0.9.1.xar ${autodeploy}
ADD http://exist-db.org/exist/apps/public-repo/public/expath-crypto-exist-lib-0.6.xar ${autodeploy}
# ADD http://exist-db.org:8098/exist/apps/public-repo/public/exist-sparql-0.1-SNAPSHOT.xar ${autodeploy}


# Copy built eXist package to autodeploy 
COPY build/*.xar ${autodeploy}

# OPTIONAL: Copy custom conf.xml to WEB-INF.
# Removed this because some of the configuration settings were causing errors during deployment.
# COPY conf/conf.xml /exist/etc

# OPTIONAL: Copy custom controller-config.xml to WEB-INF. This sets the root app to srophe.
COPY conf/controller-config.xml /exist/etc/webapp/WEB-INF/

# OPTIONAL: Copy custom jetty config to set context to '/'
# See: https://exist-open.markmail.org/message/gjp2po2ducmckvix?q=set+app+as+root+order:date-backward
COPY conf/exist-webapp-context.xml /exist/etc/jetty/webapps/

EXPOSE 8080 8443

# Start eXist-db
CMD [ "java", "-jar", "start.jar", "jetty" ]

LABEL org.opencontainers.image.source=https://github.com/biblia-arabica/srophe-eXist-app
FROM dockerproductionaws/microtrader-dev
MAINTAINER Justin Menga <justin.menga@gmail.com>
LABEL application=trader-dashboard

# Copy just the POM and bower.json first
COPY pom.xml /app/
COPY src/main/resources/webroot/bower.json /app/src/main/resources/webroot/bower.json
WORKDIR /app

# Install bower
RUN apk add --no-cache nodejs git && \
    npm install bower -g

# Install dependencies 
# We call versions:set to force dependences for the version plugin to be installed
RUN mvn versions:set clean install

# Copy the application source and set the app version
COPY src /app/src
ARG app_version
RUN mvn versions:set -DnewVersion=${app_version}
FROM dpaws/microtrader-dev
MAINTAINER Justin Menga <justin.menga@gmail.com>
LABEL application=trader-dashboard

# Install bower
RUN apk add --no-cache nodejs git

# Copy just the POM and bower.json first
# Git plugins are deactivated if APP_VERSION is set
ENV APP_VERSION=snapshot
COPY pom.xml /app/
COPY src/main/resources/webroot/bower.json /app/src/main/resources/webroot/bower.json
WORKDIR /app

# Install bower components
RUN npm install bower -g

# Install dependencies 
RUN mvn clean install

# Set the app version and copy the application source
ARG app_version
ENV APP_VERSION=${app_version}
COPY src /app/src

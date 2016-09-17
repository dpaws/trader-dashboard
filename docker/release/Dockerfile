FROM dockerproductionaws/microtrader-base
MAINTAINER Justin Menga <justin.menga@gmail.com>
LABEL application=trader-dashboard

# Copy application artefacts
ARG app_version
ENV app_version $app_version
COPY target/trader-dashboard-${app_version}-fat.jar /app/

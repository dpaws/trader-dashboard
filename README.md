# Docker in Production using AWS - Trader Dashboard

This application is part of the sample application included with the Pluralsight course Docker in Production using Amazon Web Services.

## Quick Start

To run tests and create an application "fat" JAR:

```
$ make test
```

This will build a development image, run tests and create a fat JAR that is output to the local `target` folder.

To run the fat JAR:

```
$ java -jar target/trader-dashboard-0.1.0-fat.jar -conf=src/conf/config.json
Sep 07, 2016 1:12:32 AM io.vertx.core.impl.launcher.commands.VertxIsolatedDeployer
INFO: Succeeded in deploying verticle
Server started

```

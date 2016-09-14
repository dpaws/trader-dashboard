package com.pluralsight.dockerproductionaws.traderdashboard;

import com.pluralsight.dockerproductionaws.common.MicroserviceVerticle;
import io.vertx.circuitbreaker.CircuitBreaker;
import io.vertx.circuitbreaker.CircuitBreakerOptions;
import io.vertx.core.buffer.Buffer;
import io.vertx.core.http.HttpClient;
import io.vertx.core.http.HttpClientOptions;
import io.vertx.core.http.HttpServerResponse;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import io.vertx.ext.web.handler.StaticHandler;
import io.vertx.ext.web.handler.sockjs.BridgeOptions;
import io.vertx.ext.web.handler.sockjs.PermittedOptions;
import io.vertx.ext.web.handler.sockjs.SockJSHandler;
import io.vertx.servicediscovery.ServiceDiscovery;
import io.vertx.servicediscovery.ServiceDiscoveryOptions;
import io.vertx.servicediscovery.rest.ServiceDiscoveryRestEndpoint;

/**
 * Created by jmenga on 12/09/16.
 */
public class DashboardVerticle extends MicroserviceVerticle {
    private CircuitBreaker circuit;
    private HttpClient client;

    @Override
    public void start() {
        discovery = ServiceDiscovery.create(vertx, new ServiceDiscoveryOptions().setBackendConfiguration(config()));
        Router router = Router.router(vertx);

        // Http Client
        HttpClientOptions clientOptions = new HttpClientOptions().setDefaultHost(config().getString("AUDIT_HOST"));
        clientOptions.setDefaultPort(config().getInteger("AUDIT_PORT"));
        client = vertx.createHttpClient(clientOptions);

        // Event bus bridge
        SockJSHandler sockJSHandler = SockJSHandler.create(vertx);
        BridgeOptions options = new BridgeOptions();
        options
                .addOutboundPermitted(new PermittedOptions().setAddress(config().getString("MARKET_DATA_ADDRESS")))
                .addOutboundPermitted(new PermittedOptions().setAddress(config().getString("PORTFOLIO_ADDRESS")))
                .addOutboundPermitted(new PermittedOptions().setAddress("service.portfolio"))
                .addInboundPermitted(new PermittedOptions().setAddress("service.portfolio"))
                .addOutboundPermitted(new PermittedOptions().setAddress("vertx.circuit-breaker"));

        sockJSHandler.bridge(options);
        router.route("/eventbus/*").handler(sockJSHandler);

        // Discovery endpoint
        ServiceDiscoveryRestEndpoint.create(router, discovery);

        // Last operations
        router.get("/operations").handler(this::callAuditServiceWithExceptionHandlerWithCircuitBreaker);

        // Static content
        router.route("/*").handler(StaticHandler.create());

        // Create a circuit breaker.
        circuit = CircuitBreaker.create("http-audit-service", vertx,
                new CircuitBreakerOptions()
                        .setMaxFailures(2)
                        .setFallbackOnFailure(true)
                        .setResetTimeout(2000)
                        .setTimeout(1000));

        vertx.createHttpServer()
                .requestHandler(router::accept)
                .listen(config().getInteger("HTTP_PORT"));
    }

    private void callAuditServiceWithExceptionHandlerWithCircuitBreaker(RoutingContext context) {
        HttpServerResponse resp = context.response()
                .putHeader("content-type", "application/json")
                .setStatusCode(200);

        circuit.executeWithFallback(
                future ->
                        client.get("/", response -> {
                            response
                                    .exceptionHandler(future::fail)
                                    .bodyHandler(future::complete);
                        })
                                .exceptionHandler(future::fail)
                                .setTimeout(5000)
                                .end(),
                t -> Buffer.buffer("{\"message\":\"No audit service, or unable to call it\"}")
        )
                .setHandler(ar -> resp.end(ar.result()));
    }
}

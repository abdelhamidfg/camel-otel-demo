package com.redhat;

import org.apache.camel.Exchange;
import org.apache.camel.Processor;
import io.opentelemetry.api.trace.Span;
import io.quarkus.arc.Unremovable;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.common.AttributeKey;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Named;
import jakarta.inject.Singleton;

@Named("messageProcessor")
@Singleton
@Unremovable
//@ApplicationScoped

public class MessageProcessor implements Processor {
    @Override
    public void process(Exchange exchange) {
        String body=exchange.getIn().getBody(String.class);        
        Span.current().addEvent("EndPoint uri="+exchange.getFromEndpoint().getEndpointUri()+" Message Body="+body);
    }
}

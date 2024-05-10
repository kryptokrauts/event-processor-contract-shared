package com.kryptokrauts.sync;

import io.smallrye.common.annotation.Identifier;
import io.smallrye.mutiny.Uni;
import io.smallrye.reactive.messaging.kafka.DeserializationFailureHandler;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import org.apache.avro.specific.SpecificRecordBase;
import org.apache.kafka.common.header.Headers;
import org.jboss.logging.Logger;

@ApplicationScoped
@Identifier("avro-deserialization-failure-handler")
public class AvroDeserializationFailureHandler
    implements DeserializationFailureHandler<SpecificRecordBase> {

  protected static final Logger logger = Logger.getLogger(AvroDeserializationFailureHandler.class);

  @Override
  public SpecificRecordBase handleDeserializationFailure(
      String topic,
      boolean isKey,
      String deserializer,
      byte[] data,
      Exception exception,
      Headers headers) {

    StringBuffer buffer = new StringBuffer();
    headers.forEach(h -> buffer.append(h.key() + ":" + h.value()));
    throw new RuntimeException(
        String.format("Error deserializing message of type %s: %s", buffer.toString(), data));
  }

  @Override
  public SpecificRecordBase decorateDeserialization(
      Uni<SpecificRecordBase> deserialization,
      String topic,
      boolean isKey,
      String deserializer,
      byte[] data,
      Headers headers) {

    return deserialization
        .onFailure()
        .retry()
        .withBackOff(Duration.ofSeconds(1))
        .atMost(10)
        .await()
        .atMost(Duration.ofSeconds(60));
  }
}

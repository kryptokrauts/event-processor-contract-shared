package com.kryptokrauts.shared.contract.handlers;

import io.smallrye.common.annotation.Identifier;
import io.smallrye.mutiny.Uni;
import io.smallrye.reactive.messaging.kafka.SerializationFailureHandler;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import org.apache.avro.specific.SpecificRecordBase;
import org.apache.kafka.common.header.Headers;
import org.jboss.logging.Logger;

@ApplicationScoped
@Identifier("avro-serialization-fallback-handler")
public class AvroSerializationFailureHandler
    implements SerializationFailureHandler<SpecificRecordBase> {

  protected static final Logger logger = Logger.getLogger(AvroSerializationFailureHandler.class);

  @Override
  public byte[] handleSerializationFailure(
      String topic,
      boolean isKey,
      String serializer,
      SpecificRecordBase data,
      Exception exception,
      Headers headers) {

    StringBuffer buffer = new StringBuffer();
    headers.forEach(h -> buffer.append(h.key() + ":" + h.value()));
    throw new RuntimeException(
        String.format("Error serializing of type %s: %s", buffer.toString(), data));
  }

  @Override
  public byte[] decorateSerialization(
      Uni<byte[]> serialization,
      String topic,
      boolean isKey,
      String serializer,
      SpecificRecordBase data,
      Headers headers) {
    return serialization
        .onFailure()
        .retry()
        .withBackOff(Duration.ofSeconds(1))
        .atMost(10)
        .await()
        .atMost(Duration.ofSeconds(60));
  }
}

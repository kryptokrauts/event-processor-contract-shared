package com.kryptokrauts.shared.contract.handlers;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.kryptokrauts.shared.contract.types.RawEvent;
import contracts.realtime_event;
import io.smallrye.reactive.messaging.kafka.api.OutgoingKafkaRecordMetadata;
import jakarta.inject.Inject;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import org.apache.commons.beanutils.BeanUtils;
import org.apache.commons.lang3.StringUtils;
import org.apache.kafka.common.header.internals.RecordHeaders;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Message;
import org.jboss.logging.Logger;

public abstract class BaseHandler {

  @Inject protected ObjectMapper objectMapper;

  @Inject
  @Channel("realtime")
  Emitter<realtime_event> realtimeEventEmitter;

  protected static final Logger logger = Logger.getLogger(BaseHandler.class);

  protected void emitRealtimeMessage(RawEvent event, Map<String, Object> dataMap, String context)
      throws Exception {
    BaseHandler.logger.debugf(
        "Emitting realtime message for event '%s' at blocknum %d",
        event.getType(), event.getBlocknum());

    realtime_event transformed = new realtime_event();
    transformed.setBlocknum(event.getBlocknum());
    transformed.setBlockTimestamp(event.getTimestamp());
    transformed.setContext(context);
    transformed.setType(event.getType());
    transformed.setData(this.objectMapper.writeValueAsString(dataMap));

    this.emitTransformedMessage(transformed, realtimeEventEmitter);
  }

  private OutgoingKafkaRecordMetadata<?> createHeader(String className) {
    return OutgoingKafkaRecordMetadata.builder()
        .withHeaders(new RecordHeaders().add(className, "true".getBytes(StandardCharsets.UTF_8)))
        .build();
  }

  protected <T> void emitTransformedMessage(T msg, Emitter<T> emitter) {
    emitter.send(Message.of(msg).addMetadata(this.createHeader(msg.getClass().getSimpleName())));
  }

  protected void logDebugStartHandleEvent(RawEvent event) {
    BaseHandler.logger.debugf(
        "Handle incoming '%s' event at blocknum %d", event.getType(), event.getBlocknum());
  }

  protected void copyProperties(Object dest, Object src) {
    try {
      BeanUtils.copyProperties(dest, src);
    } catch (Exception e) {
      BaseHandler.logger.warnf(e, "Error copying object from %o to %o", src, dest);
    }
  }

  protected String getSanitizedString(RawEvent event, String key) {
    return this.getSanitizedObject(event, key);
  }

  protected Boolean getSanitizedBoolean(RawEvent event, String key) {
    return this.getSanitizedObject(event, key);
  }

  protected Long getSanitizedLong(RawEvent event, String key) {
    Object value = this.getSanitizedObject(event, key);
    if (value != null) {
      return Long.valueOf(value.toString());
    }
    return null;
  }

  protected Integer getSanitizedInt(RawEvent event, String key) {
    Object value = this.getSanitizedObject(event, key);
    if (value != null) {
      return Integer.parseInt(value.toString());
    }
    return null;
  }

  protected Double getSanitizedDouble(RawEvent event, String key) {
    Object value = this.getSanitizedObject(event, key);
    if (value != null) {
      return Double.parseDouble(value.toString());
    }
    return null;
  }

  @SuppressWarnings("unchecked")
  protected <T> T getSanitizedObject(RawEvent event, String key) {
    if (event.getData() != null) {
      try {
        Map<String, Object> dataMap = (Map<String, Object>) event.getData();
        return (T) dataMap.get(key);
      } catch (Exception e) {
        BaseHandler.logger.warnf(e, "Error retrieving key %s from rawEvent.data", key);
      }
    }
    return null;
  }

  protected String getValueForKey(Map<String, Object> data, String key) {
    return this.getValueForKeys(data, List.of(key));
  }

  protected String getValueForKeys(Map<String, Object> data, List<String> keys) {
    if (data != null && data.size() > 0) {
      return keys.stream()
          .filter(p -> data.containsKey(p))
          .filter(p -> StringUtils.isNotBlank(data.get(p).toString()))
          .map(p -> data.get(p).toString())
          .findFirst()
          .orElse(null);
    }
    return null;
  }
}

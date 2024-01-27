package com.kryptokrauts.shared.contract;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.kryptokrauts.shared.entity.EventLogEntity;
import com.kryptokrauts.shared.resources.ApicurioTestResource;
import com.kryptokrauts.shared.resources.ExtendedKafkaCompanionTestResource;
import com.kryptokrauts.shared.resources.KafkaConnectImporterTestResource;
import com.kryptokrauts.shared.resources.KafkaConnectTestResource;
import com.kryptokrauts.shared.resources.PostgresTestResource;
import contracts.event_log;
import io.apicurio.registry.serde.SerdeConfig;
import io.apicurio.registry.serde.avro.AvroKafkaDeserializer;
import io.apicurio.registry.serde.avro.AvroKafkaSerdeConfig;
import io.apicurio.registry.serde.avro.AvroKafkaSerializer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.kafka.InjectKafkaCompanion;
import io.restassured.RestAssured;
import io.smallrye.reactive.messaging.kafka.companion.ConsumerTask;
import io.smallrye.reactive.messaging.kafka.companion.KafkaCompanion;
import jakarta.transaction.Transactional;
import jakarta.transaction.Transactional.TxType;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.admin.OffsetSpec;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.header.Headers;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.apache.kafka.common.header.internals.RecordHeaders;
import org.apache.kafka.common.serialization.Deserializer;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.serialization.Serializer;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.awaitility.Awaitility;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.Network;

@QuarkusTestResource(PostgresTestResource.class)
@QuarkusTestResource(ExtendedKafkaCompanionTestResource.class)
@QuarkusTestResource(ApicurioTestResource.class)
@QuarkusTestResource(KafkaConnectTestResource.class)
@QuarkusTestResource(KafkaConnectImporterTestResource.class)
public abstract class BaseTest {

  public static final Network TEST_NETWORK = Network.newNetwork();

  @InjectKafkaCompanion protected KafkaCompanion companion;

  @ConfigProperty(name = "mp.messaging.incoming.raw.topic")
  protected String sourceTopic;

  @ConfigProperty(name = "mp.messaging.outgoing.structured.topic")
  protected String sinkTopic;

  protected abstract void _setUp(Map<String, Object> config);

  protected abstract String getTestFilesPath();

  protected ObjectMapper objectMapper = new ObjectMapper();

  private long offsetBeforeTestCase = 0;

  @BeforeEach
  void setUp() throws Exception {

    Map<String, Object> config = new HashMap<>();

    config.put(SerdeConfig.REGISTRY_URL, ApicurioTestResource.apicurioURL);
    config.put(AvroKafkaSerdeConfig.USE_SPECIFIC_AVRO_READER, true);
    config.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, this.companion.getBootstrapServers());
    config.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
    config.put(
        ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, AvroKafkaDeserializer.class.getName());
    config.put(ConsumerConfig.GROUP_ID_CONFIG, this.getClass().getName());

    this.registerSerdeFor(event_log.class, config);

    this._setUp(config);
  }

  @AfterAll
  static void finish() {
    BaseTest.TEST_NETWORK.close();
  }

  @Test()
  public void testReadyness() {
    RestAssured.when()
        .get("/q/health/ready")
        .then()
        .body(
            "status",
            Matchers.is("UP"),
            "checks.status",
            Matchers.containsInAnyOrder("UP", "UP", "UP"),
            "checks.name",
            Matchers.containsInAnyOrder(
                "Kafka connection health check",
                "SmallRye Reactive Messaging - readiness check",
                "Database connections health check"));
  }

  protected <T> void registerSerdeFor(Class<T> clazz, Map<String, Object> config) {

    Serializer<T> serializer = new AvroKafkaSerializer<>();
    Deserializer<T> deserializer = new AvroKafkaDeserializer<>();

    Serde<T> serde = Serdes.serdeFrom(serializer, deserializer);
    serde.configure(config, false);

    this.companion.registerSerde(clazz, serde);
  }

  protected long getCurrentOffset(String topic) {
    try {
      return this.companion
          .offsets()
          .get(KafkaCompanion.tp(topic, 0), OffsetSpec.latest())
          .offset();
    } catch (Exception e) {
      return 0;
    }
  }

  protected Map<TopicPartition, Long> getTopicOffset(String topic, long startOffset) {
    return Map.of(KafkaCompanion.tp(this.sinkTopic, 0), startOffset);
  }

  protected <T> long hasClassHeader(
      List<? extends ConsumerRecord<String, T>> record, String className) {
    if (record != null && record.size() > 0) {
      return record.stream().filter(p -> p.headers().lastHeader(className) != null).count();
    }
    return 0l;
  }

  /**
   * wait until expected database entity exists and return it
   *
   * @param <T>
   * @param entityQuery
   * @return
   */
  protected <T> T waitForDatabaseEntity(Supplier<T> entityQuery) {
    Awaitility.with()
        .pollInterval(Duration.ofMillis(250))
        .await()
        .atMost(Duration.ofSeconds(20))
        .dontCatchUncaughtExceptions()
        .until(
            () -> {
              return this.callWithTx(entityQuery) != null;
            });

    return this.callWithTx(entityQuery);
  }

  @Transactional(value = TxType.REQUIRED)
  protected <T> T callWithTx(Supplier<T> entityQuery) {
    return entityQuery.get();
  }

  /**
   *
   *
   * <pre>
   * insert given testCase as raw message
   * consume numRecords message from sinkTopic
   * await completion
   * check expected numRecords messages of given type
   * </pre>
   *
   * @param <T> raw type
   * @param testCase testCase
   * @param clazz class of raw type
   * @param numRecords to be expected to read
   * @return
   */
  protected <T> ConsumerTask<String, T> createKafkaRawMessageAndWaitForProcessing(
      String testCase, Class<T> clazz, long numRecords) {
    this.createTestMessage(testCase);

    return this.waitForKafkaProcessing(clazz, numRecords, 0l);
  }

  /**
   *
   *
   * <pre>
   * consume numRecords message from sinkTopic, respecting a potential offset increase because of messages of different type consumed before
   * await completion
   * check expected numRecords messages of given type
   * </pre>
   *
   * @param <T> raw type
   * @param testCase testCase
   * @param clazz class of raw type
   * @param numRecords to be expected to read
   * @return
   */
  protected <T> ConsumerTask<String, T> waitForKafkaProcessing(
      Class<T> clazz, long numRecords, long offsetIncreaseAfterTestMessage) {

    ConsumerTask<String, T> consumer =
        this.companion
            .consume(clazz)
            .fromOffsets(
                this.getTopicOffset(
                    this.sinkTopic, this.offsetBeforeTestCase + offsetIncreaseAfterTestMessage),
                numRecords);

    consumer.awaitCompletion();

    Assertions.assertEquals(
        numRecords, this.hasClassHeader(consumer.getRecords(), clazz.getSimpleName()));

    return consumer;
  }

  protected String createTestMessage(String testCase) {
    String actionType = this.createTestMessage(testCase, null);

    this.waitForKafkaProcessing(event_log.class, 1l, 0l);
    EventLogEntity eventLogEntity = getEventLogEntity(actionType);

    Assertions.assertEquals(actionType, eventLogEntity.getType());

    this.offsetBeforeTestCase++;

    return actionType;
  }

  protected abstract EventLogEntity getEventLogEntity(String actionType);

  /**
   * produce raw kafka event message for given testCase
   *
   * @param testCase
   * @param additionalHeader
   * @return action type
   */
  protected String createTestMessage(String testCase, String additionalHeader) {
    try {
      String testdata =
          Files.readString(
              Paths.get(
                  "src/test/resources/testdata/"
                      + this.getTestFilesPath()
                      + "/"
                      + testCase
                      + ".json"));
      Headers headers = new RecordHeaders();
      String rawHeaderIdentifier = testCase.replaceAll("_\\w+$", "");
      headers.add(
          new RecordHeader(
              "type", ("atomicassets." + rawHeaderIdentifier).getBytes(StandardCharsets.UTF_8)));
      if (additionalHeader != null) {
        headers.add(new RecordHeader("type", additionalHeader.getBytes(StandardCharsets.UTF_8)));
      }

      this.companion
          .produce(String.class)
          .fromRecords(new ProducerRecord<>(this.sourceTopic, 0, null, "", testdata, headers));

      this.offsetBeforeTestCase = this.getCurrentOffset(this.sinkTopic);

      return rawHeaderIdentifier;
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }
}

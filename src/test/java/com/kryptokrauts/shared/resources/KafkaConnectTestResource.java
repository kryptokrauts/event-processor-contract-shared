package com.kryptokrauts.shared.resources;

import com.kryptokrauts.shared.contract.BaseTest;
import io.apicurio.registry.serde.SerdeConfig;
import io.apicurio.registry.serde.avro.AvroKafkaDeserializer;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.awaitility.Awaitility;
import org.jboss.logging.Logger;
import org.testcontainers.containers.Container.ExecResult;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.MountableFile;

public class KafkaConnectTestResource implements QuarkusTestResourceLifecycleManager {

  protected static final Logger logger = Logger.getLogger(KafkaConnectTestResource.class);

  private GenericContainer<?> kafkaConnect;

  @Override
  @SuppressWarnings("resource")
  public void init(Map<String, String> initArgs) {
    this.kafkaConnect =
        new GenericContainer<>("ghcr.io/kryptokrauts/kafka-connect:latest")
            .withEnv("kafka.port", "9092")
            .withCopyFileToContainer(
                MountableFile.forClasspathResource("/kafka-connect/"), "/opt/bitnami/kafka/config")
            .withNetwork(BaseTest.TEST_NETWORK)
            .withNetworkAliases("kafka-connect");
  }

  @Override
  public Map<String, String> start() {
    Map<String, String> config = new HashMap<>();

    config.put(SerdeConfig.REGISTRY_URL, ApicurioTestResource.apicurioURL);
    config.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, "kafka-broker:9093");
    config.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
    config.put(
        ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, AvroKafkaDeserializer.class.getName());
    config.put(ConsumerConfig.GROUP_ID_CONFIG, this.getClass().getName());

    this.kafkaConnect.start();
    try {
      Awaitility.with()
          .pollInterval(Duration.ofSeconds(3))
          .await()
          .atMost(Duration.ofSeconds(30))
          .until(
              new Callable<Boolean>() {
                public Boolean call() throws Exception {
                  KafkaConnectTestResource.logger.info("Validating kafka connect API availability");
                  ExecResult result =
                      KafkaConnectTestResource.this.kafkaConnect.execInContainer(
                          "sh",
                          "-c",
                          "curl --output /dev/null --head --fail http://localhost:8083/connectors");
                  return 0 == result.getExitCode();
                }
              });
    } catch (Exception e) {
      e.printStackTrace();
    }
    return config;
  }

  @Override
  public void stop() {
    this.kafkaConnect.stop();
    this.kafkaConnect.close();
  }
}

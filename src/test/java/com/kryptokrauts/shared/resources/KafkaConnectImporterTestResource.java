package com.kryptokrauts.shared.resources;

import com.kryptokrauts.shared.contract.BaseTest;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.images.builder.ImageFromDockerfile;
import org.testcontainers.utility.MountableFile;

public class KafkaConnectImporterTestResource implements QuarkusTestResourceLifecycleManager {

  private GenericContainer<?> connectImporter;

  @Override
  @SuppressWarnings("resource")
  public void init(Map<String, String> initArgs) {
    Path basePath = Paths.get("../event-processor-persist");
    this.connectImporter =
        new GenericContainer<>(
                new ImageFromDockerfile("kafka-connect-importer", true)
                    .withFileFromPath("Dockerfile", basePath.resolve("Dockerfile"))
                    .withFileFromPath(
                        "import_kafka_connect_config.sh",
                        basePath.resolve("import_kafka_connect_config.sh")))
            .withEnv("KAFKA_CONNECT_ENDPOINT", "http://kafka-connect:8083/connectors")
            .withCopyFileToContainer(
                MountableFile.forHostPath(
                    Paths.get(basePath.toAbsolutePath().toString(), "/config")),
                "/config")
            .withNetwork(BaseTest.TEST_NETWORK);
  }

  @Override
  public Map<String, String> start() {
    this.connectImporter.start();
    Map<String, String> properties = new HashMap<>();

    return properties;
  }

  @Override
  public void stop() {
    this.connectImporter.stop();
    this.connectImporter.close();
  }
}

package com.kryptokrauts.shared.resources;

import com.kryptokrauts.shared.contract.BaseTest;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import java.util.HashMap;
import java.util.Map;
import org.testcontainers.containers.GenericContainer;

public class ApicurioTestResource implements QuarkusTestResourceLifecycleManager {

  private GenericContainer<?> registry;

  public static String apicurioURL = "http://registry:8080/apis/registry/v2";

  @Override
  @SuppressWarnings("resource")
  public void init(Map<String, String> initArgs) {
    this.registry =
        new GenericContainer<>("apicurio/apicurio-registry-sql:2.5.7.Final")
            .withExposedPorts(8080)
            .withEnv("QUARKUS_PROFILE", "prod")
            .withEnv("quarkus.datasource.jdbc.url", "jdbc:postgresql://postgres/apicurio")
            .withEnv("quarkus.datasource.password", "apicurio")
            .withEnv("quarkus.datasource.username", "apicurio")
            .withEnv("quarkus.datasource.db-kind", "postgresql")
            .withNetwork(BaseTest.TEST_NETWORK)
            .withNetworkAliases("registry");
  }

  @Override
  public Map<String, String> start() {
    String registryUrlKey = "mp.messaging.connector.smallrye-kafka.apicurio.registry.url";

    this.registry.start();
    Map<String, String> properties = new HashMap<>();
    properties.put(
        registryUrlKey,
        "http://"
            + this.registry.getHost()
            + ":"
            + this.registry.getMappedPort(8080)
            + "/apis/registry/v2");
    ApicurioTestResource.apicurioURL = properties.get(registryUrlKey);
    return properties;
  }

  @Override
  public void stop() {
    this.registry.stop();
    this.registry.close();
  }
}

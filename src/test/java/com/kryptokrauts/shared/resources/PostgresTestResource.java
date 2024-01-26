package com.kryptokrauts.shared.resources;

import com.google.common.collect.ImmutableMap;
import com.kryptokrauts.shared.contract.BaseTest;
import io.quarkus.test.common.DevServicesContext;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import java.util.Map;
import java.util.Optional;
import org.testcontainers.containers.PostgreSQLContainer;

public class PostgresTestResource
    implements QuarkusTestResourceLifecycleManager, DevServicesContext.ContextAware {

  private Optional<String> containerNetworkId;
  private PostgreSQLContainer<?> container;

  @Override
  public void setIntegrationTestContext(DevServicesContext context) {
    this.containerNetworkId = context.containerNetworkId();
  }

  @Override
  @SuppressWarnings("resource")
  public void init(Map<String, String> initArgs) {
    this.container =
        new PostgreSQLContainer<>("postgres:15-alpine")
            .withDatabaseName("soon_market_internal")
            .withUsername("kafka")
            .withPassword("kafka")
            .withNetwork(BaseTest.TEST_NETWORK)
            .withInitScript("shared/init_test_container_databases.sql")
            .withNetworkAliases("postgres");

    this.containerNetworkId.ifPresent(this.container::withNetworkMode);
  }

  @Override
  public Map<String, String> start() {

    // start container before retrieving its URL or other properties
    this.container.start();

    String jdbcUrl = this.container.getJdbcUrl();
    if (this.containerNetworkId.isPresent()) {
      // Replace hostname + port in the provided JDBC URL with the hostname of the Docker container
      // running PostgreSQL and the listening port.
      jdbcUrl = this.fixJdbcUrl(jdbcUrl);
    }

    // return a map containing the configuration the application needs to use the service
    return ImmutableMap.of(
        "quarkus.datasource.username", this.container.getUsername(),
        "quarkus.datasource.password", this.container.getPassword(),
        "quarkus.datasource.jdbc.url", jdbcUrl);
  }

  private String fixJdbcUrl(String jdbcUrl) {
    // Part of the JDBC URL to replace
    String hostPort =
        this.container.getHost()
            + ':'
            + this.container.getMappedPort(PostgreSQLContainer.POSTGRESQL_PORT);

    // Host/IP on the container network plus the unmapped port
    String networkHostPort =
        this.container.getCurrentContainerInfo().getConfig().getHostName()
            + ':'
            + PostgreSQLContainer.POSTGRESQL_PORT;

    return jdbcUrl.replace(hostPort, networkHostPort);
  }

  @Override
  public void stop() {
    this.container.stop();
    this.container.close();
  }
}

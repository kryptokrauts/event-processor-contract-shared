package com.kryptokrauts.shared.resources;

import com.kryptokrauts.shared.contract.BaseTest;
import io.quarkus.test.kafka.KafkaCompanionResource;
import java.util.Map;

public class ExtendedKafkaCompanionTestResource extends KafkaCompanionResource {

  @Override
  public Map<String, String> start() {

    if (this.kafka != null) {
      this.kafka = this.kafka.withNetwork(BaseTest.TEST_NETWORK).withNetworkAliases("kafka-broker");
    }
    Map<String, String> props = super.start();

    return props;
  }

  @Override
  public void stop() {
    super.stop();
  }
}

package com.kryptokrauts.shared.dao.common;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "soonmarket_exchange_rate_latest_v")
public class ExchangeRateEntity extends PanacheEntityBase {

  @Id private String tokenSymbol;

  private Double usd;
}

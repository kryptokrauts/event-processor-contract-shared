package com.kryptokrauts.shared.dao.common;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_exchange_rate_latest_v")
public class ExchangeRateEntity extends PanacheEntityBase {

  @Id private String tokenSymbol;

  private Double usd;

  public static ExchangeRateEntity findByToken(String token) {
    return ExchangeRateEntity.find("tokenSymbol = ?1", token).firstResult();
  }
}

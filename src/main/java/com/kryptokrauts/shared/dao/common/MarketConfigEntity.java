package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._MarketConfig;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "atomicmarket_config")
public class MarketConfigEntity extends PanacheEntityBase {

  @Id private Long id;

  private Double maker_fee;

  private Double taker_fee;

  private Double auctionMinBidIncrease;

  public _MarketConfig toModel() {
    if (this.id != null) {
      return _MarketConfig.builder()
          .id(this.id)
          .maker_fee(this.maker_fee)
          .taker_fee(this.taker_fee)
          .auctionMinBidIncrease(this.auctionMinBidIncrease)
          .build();
    }
    return null;
  }
}

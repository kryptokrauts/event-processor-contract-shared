package com.kryptokrauts.shared.model.common;

import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Builder
@RegisterForReflection
public class _MarketConfig {

  private Long id;

  private Double maker_fee;

  private Double taker_fee;

  private Double auctionMinBidIncrease;

  public Double getMarketFee() {
    return this.maker_fee + this.taker_fee;
  }
}

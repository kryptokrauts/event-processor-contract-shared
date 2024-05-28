package com.kryptokrauts.shared.model.realtime.task;

import com.kryptokrauts.shared.enums.MarketType;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Task;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
public class _InvalidOffer extends _Task {

  private Long buyofferId;

  private _PriceInfo price;

  @Override
  public MarketType getMarketType() {
    return MarketType.buyoffer;
  }
}

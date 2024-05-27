package com.kryptokrauts.shared.model.realtime.task;

import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Task;
import com.kryptokrauts.soonmarket.api.common.Enums.MarketType;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
public class _AuctionEndZeroBids extends _Task {

  private _PriceInfo startingBid;

  private Long auctionId;

  @Override
  public MarketType getMarketType() {
    return MarketType.auction;
  }
}

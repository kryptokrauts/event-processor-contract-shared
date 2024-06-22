package com.kryptokrauts.shared.model.realtime.task;

import com.kryptokrauts.shared.enums.MarketType;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Task;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
@AllArgsConstructor
@NoArgsConstructor
public class _InvalidListing extends _Task {

  private Long listingId;

  private _PriceInfo price;

  @Override
  public MarketType getMarketType() {
    return MarketType.listing;
  }
}

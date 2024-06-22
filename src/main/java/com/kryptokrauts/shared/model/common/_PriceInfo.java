package com.kryptokrauts.shared.model.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonInclude.Include;
import com.kryptokrauts.shared.model._BaseModel;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@JsonInclude(Include.NON_NULL)
@Getter
@Setter
@RegisterForReflection
@AllArgsConstructor
@NoArgsConstructor
@SuperBuilder
public class _PriceInfo extends _BaseModel {

  private String paymentAsset;

  private Double price;

  private Double priceUSD;

  private Double sellerReceivedPrice;

  private Double sellerReceivedPriceUSD;

  private Double royalty;

  private Double royaltyPrice;

  private Double royaltyUSD;

  private Double makerMarketFee;

  private Double takerMarketFee;

  private Double marketFeePrice;

  private Double marketFeeUSD;

  private Double makerMarketFeeUSD;

  private Double takerMarketFeeUSD;

  private String rawPrice;

  private Boolean bundle;
}

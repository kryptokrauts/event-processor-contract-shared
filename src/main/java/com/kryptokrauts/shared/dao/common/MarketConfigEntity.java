package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._MarketConfig;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
@Table(name = "atomicmarket_config")
public class MarketConfigEntity extends PanacheEntityBase {

  @Id private Long id;

  private Long blocknum;

  private Long blockTimestamp;

  private Double makerFee;

  private Double takerFee;

  private String version;

  private Integer auctionMinDurationSeconds;

  private Integer auctionMaxDurationSeconds;

  private Double auctionMinBidIncrease;

  private Integer auctionResetDurationSeconds;

  public Double getMarketFee() {
    return makerFee + takerFee;
  }

  public static MarketConfigEntity findOrGetNew(String version, Long blocknum) {
    MarketConfigEntity entity =
        MarketConfigEntity.find("version = ?1 AND blocknum", version, blocknum).firstResult();
    if (entity == null) {
      entity = new MarketConfigEntity();
    }
    return entity;
  }

  public static MarketConfigEntity findLatest() {
    return MarketConfigEntity.findAll(Sort.descending("id")).firstResult();
  }

  public _MarketConfig toModel() {
    if (this.id != null) {
      return _MarketConfig.builder()
          .id(this.id)
          .maker_fee(this.makerFee)
          .taker_fee(this.takerFee)
          .auctionMinBidIncrease(this.auctionMinBidIncrease)
          .build();
    }
    return null;
  }
}

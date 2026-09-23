package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._MarketConfig;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

/*-
 * read model for atomicmarket_config. Reads only.
 *
 * The id deliberately carries no @GeneratedValue while the column is a bigserial, so persisting a
 * new row through this class fails on identifier generation. That is the point: writes belong to
 * the processor that owns them, through its own entity, and this class exists so the consumers
 * that vendor this library can read the config without depending on the processor.
 *
 * Use findLatest() and toModel(). To write a config row, use event-processor-contract's
 * com.kryptokrauts.dao.atomicmarket.config.MarketConfigEntity, which extends BaseEntity and has
 * the mapping for it.
 *
 * A findOrGetNew() used to live here, and a handler picked it up instead of the processor's own
 * entity - an import away from the one it meant. Its query was also invalid HQL, which is what
 * halted the contract processor for a day when atomicmarket first changed the minimum bid
 * increase, two years after the method was written. See kryptokrauts/event-processor-contract#86.
 * Nothing called it by then, so it was removed rather than repaired: repairing the predicate would
 * have left a method that still could not write, on a class that is not meant to.
 */
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

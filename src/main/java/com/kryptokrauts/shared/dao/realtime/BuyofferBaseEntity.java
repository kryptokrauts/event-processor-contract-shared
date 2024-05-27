package com.kryptokrauts.shared.dao.realtime;

import com.kryptokrauts.shared.dao.embeddables.Price;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "soonmarket_buyoffer_v")
public class BuyofferBaseEntity extends PanacheEntityBase {

  @Id private Long buyofferId;

  @Id private Long assetId;

  private Boolean bundle;

  private Integer bundleSize;

  private String collectionId;

  // to
  private String buyer;

  // from
  private String seller;

  private Price price;

  private String memo;

  private String declineMemo;

  private Integer index;

  public static BuyofferBaseEntity findByBuyofferId(Long buyofferId) {
    return BuyofferBaseEntity.find("buyofferId = ?1 AND index=1", buyofferId).firstResult();
  }
}

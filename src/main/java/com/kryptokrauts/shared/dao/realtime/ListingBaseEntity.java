package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "atomicmarket_sale")
public class ListingBaseEntity extends PanacheEntityBase {

  @Id private Long saleId;

  private Long primaryAssetId;

  private Double price;

  private String token;

  private Double collectionFee;

  private Boolean bundle;

  private Integer bundleSize;

  private String collectionId;

  public static ListingBaseEntity findByListingId(Long listingId) {
    return ListingBaseEntity.find("saleId = ?1", listingId).firstResult();
  }
}

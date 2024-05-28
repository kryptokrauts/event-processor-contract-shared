package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_listing_open_v")
public class OpenListingBaseEntity extends PanacheEntityBase {

  @Id private Long listingId;

  private Long assetId;

  private Double listingRoyalty;

  private Boolean bundle;

  private Integer bundleSize;

  private String collectionId;

  private Integer index;

  public static OpenListingBaseEntity findByListingId(Long listingId) {
    return OpenListingBaseEntity.find("listingId = ?1 AND index = 1", listingId).firstResult();
  }
}

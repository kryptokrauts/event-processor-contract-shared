package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_auction_base_v")
public class AuctionBaseEntity extends PanacheEntityBase {

  @Id private Long auctionId;

  @Id private Long assetId;

  private String token;

  private Double collectionFee;

  private Double currentBid;

  private Boolean bundle;

  private Integer bundleSize;

  private String collectionId;

  private Integer index;

  private String highestBidder;

  public static AuctionBaseEntity findByAuctionId(Long auctionId) {
    return AuctionBaseEntity.find("auctionId = ?1 AND index=1", auctionId).firstResult();
  }

  public static Long findNFTByAuctionId(Long auctionId) {
    AuctionBaseEntity auction = AuctionBaseEntity.findByAuctionId(auctionId);
    return auction != null ? auction.getAssetId() : null;
  }
}

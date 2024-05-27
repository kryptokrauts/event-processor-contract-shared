package com.kryptokrauts.shared.dao.realtime;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._Collection;
import com.kryptokrauts.shared.model.realtime._Task;
import com.kryptokrauts.shared.model.realtime.task._AuctionEndClaimNFTs;
import com.kryptokrauts.shared.model.realtime.task._AuctionEndZeroBids;
import com.kryptokrauts.shared.model.realtime.task._InvalidListing;
import com.kryptokrauts.shared.model.realtime.task._InvalidOffer;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;
import org.apache.commons.lang3.StringUtils;

@Getter
@Entity(name = "soonmarket_open_task_v")
public class TaskEntity extends PanacheEntityBase {

  @Id private String id;

  private String account;

  private Long blockTimestamp;

  private Long auctionId;

  private Long listingId;

  private Long buyofferId;

  private String taskType;

  private Boolean bundle;

  private Integer bundleSize;

  private Double price;

  private String token;

  /** asset info */
  private Long assetId;

  private String assetName;

  private String assetMediaType;

  private String assetMedia;

  private String assetMediaPreview;

  private Long editionSize;

  private Long serial;

  /** collection info */
  private String collectionId;

  private String collectionName;

  private String collectionImage;

  private Boolean shielded;

  private Boolean blacklisted;

  public _Task toModel() {
    if (id != null && StringUtils.isNotBlank(taskType)) {
      return switch (taskType) {
        case "auction_won_claim_nfts" -> toAuctionEndTask();
        case "auction_sold_claim_funds" -> toAuctionEndTask();
        case "auction_end_zero_bids" -> toAuctionZeroBids();
        case "invalid_listing" -> toInvalidListing();
        case "invalid_offer" -> toInvalidOffer();
        default -> null;
      };
    }
    return null;
  }

  private _AuctionEndClaimNFTs toAuctionEndTask() {
    return _AuctionEndClaimNFTs.builder()
        .asset(toAsset())
        .auctionId(auctionId)
        .bundleSize(bundleSize)
        .bundle(bundle)
        .collection(toCollection())
        .type(taskType)
        .winningBid(BaseMapper.buildPriceInfo(token, price, null))
        .build();
  }

  private _AuctionEndZeroBids toAuctionZeroBids() {
    return _AuctionEndZeroBids.builder()
        .asset(toAsset())
        .auctionId(auctionId)
        .bundleSize(bundleSize)
        .bundle(bundle)
        .collection(toCollection())
        .type(taskType)
        .startingBid(BaseMapper.buildPriceInfo(token, price, null))
        .build();
  }

  private _InvalidListing toInvalidListing() {
    return _InvalidListing.builder()
        .asset(toAsset())
        .listingId(listingId)
        .bundleSize(bundleSize)
        .bundle(bundle)
        .collection(toCollection())
        .type(taskType)
        .price(BaseMapper.buildPriceInfo(token, price, null))
        .build();
  }

  private _InvalidOffer toInvalidOffer() {
    return _InvalidOffer.builder()
        .asset(toAsset())
        .buyofferId(buyofferId)
        .bundleSize(bundleSize)
        .bundle(bundle)
        .collection(toCollection())
        .type(taskType)
        .price(BaseMapper.buildPriceInfo(token, price, null))
        .build();
  }

  private _Collection toCollection() {
    return _Collection.builder()
        .blacklisted(blacklisted)
        .collectionId(collectionId)
        .collectionImage(collectionImage)
        .collectionName(collectionName)
        .shielded(shielded)
        .build();
  }

  private _Asset toAsset() {
    return _Asset.builder()
        .assetId(assetId)
        .assetMedia(assetMedia)
        .assetMediaPreview(assetMediaPreview)
        .assetMediaType(assetMediaType)
        .assetName(assetName)
        .editionSize(editionSize)
        .serial(serial)
        .build();
  }
}

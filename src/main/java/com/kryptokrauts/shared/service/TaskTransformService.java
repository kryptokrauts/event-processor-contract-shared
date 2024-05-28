package com.kryptokrauts.shared.service;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.dao.realtime.TaskEntity;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._Collection;
import com.kryptokrauts.shared.model.realtime._Task;
import com.kryptokrauts.shared.model.realtime.task._AuctionEndClaimNFTs;
import com.kryptokrauts.shared.model.realtime.task._AuctionEndZeroBids;
import com.kryptokrauts.shared.model.realtime.task._InvalidListing;
import com.kryptokrauts.shared.model.realtime.task._InvalidOffer;
import jakarta.enterprise.context.ApplicationScoped;
import org.apache.commons.lang3.StringUtils;

@ApplicationScoped
public class TaskTransformService {

  public _Task toModel(TaskEntity task) {
    if (task.getId() != null && StringUtils.isNotBlank(task.getTaskType())) {
      return switch (task.getTaskType()) {
        case "auction_won_claim_nfts" -> toAuctionEndTask(task);
        case "auction_sold_claim_funds" -> toAuctionEndTask(task);
        case "auction_end_zero_bids" -> toAuctionZeroBids(task);
        case "invalid_listing" -> toInvalidListing(task);
        case "invalid_offer" -> toInvalidOffer(task);
        default -> null;
      };
    }
    return null;
  }

  private _AuctionEndClaimNFTs toAuctionEndTask(TaskEntity task) {
    return _AuctionEndClaimNFTs.builder()
        .asset(toAsset(task))
        .auctionId(task.getActionId())
        .bundleSize(task.getBundleSize())
        .bundle(task.getBundle())
        .collection(toCollection(task))
        .type(task.getTaskType())
        .winningBid(BaseMapper.buildPriceInfo(task.getToken(), task.getPrice(), null))
        .build();
  }

  private _AuctionEndZeroBids toAuctionZeroBids(TaskEntity task) {
    return _AuctionEndZeroBids.builder()
        .asset(toAsset(task))
        .auctionId(task.getActionId())
        .bundleSize(task.getBundleSize())
        .bundle(task.getBundle())
        .collection(toCollection(task))
        .type(task.getTaskType())
        .startingBid(BaseMapper.buildPriceInfo(task.getToken(), task.getPrice(), null))
        .build();
  }

  private _InvalidListing toInvalidListing(TaskEntity task) {
    return _InvalidListing.builder()
        .asset(toAsset(task))
        .listingId(task.getActionId())
        .bundleSize(task.getBundleSize())
        .bundle(task.getBundle())
        .collection(toCollection(task))
        .type(task.getTaskType())
        .price(BaseMapper.buildPriceInfo(task.getToken(), task.getPrice(), null))
        .build();
  }

  private _InvalidOffer toInvalidOffer(TaskEntity task) {
    return _InvalidOffer.builder()
        .asset(toAsset(task))
        .buyofferId(task.getActionId())
        .bundleSize(task.getBundleSize())
        .bundle(task.getBundle())
        .collection(toCollection(task))
        .type(task.getTaskType())
        .price(BaseMapper.buildPriceInfo(task.getToken(), task.getPrice(), null))
        .build();
  }

  private _Collection toCollection(TaskEntity task) {
    return _Collection.builder()
        .blacklisted(task.getBlacklisted())
        .collectionId(task.getCollectionId())
        .collectionImage(task.getCollectionImage())
        .collectionName(task.getCollectionName())
        .shielded(task.getShielded())
        .build();
  }

  private _Asset toAsset(TaskEntity task) {
    return _Asset.builder()
        .assetId(task.getAssetId())
        .assetMedia(task.getAssetMedia())
        .assetMediaPreview(task.getAssetMediaPreview())
        .assetMediaType(task.getAssetMediaType())
        .assetName(task.getAssetName())
        .editionSize(task.getEditionSize())
        .serial(task.getSerial())
        .build();
  }
}

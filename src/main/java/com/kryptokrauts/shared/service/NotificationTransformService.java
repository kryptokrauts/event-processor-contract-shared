package com.kryptokrauts.shared.service;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.contract.types.NotificationType;
import com.kryptokrauts.shared.dao.common.AssetBaseEntity;
import com.kryptokrauts.shared.dao.common.CollectionBaseView;
import com.kryptokrauts.shared.dao.realtime.AuctionBaseEntity;
import com.kryptokrauts.shared.dao.realtime.BuyofferBaseEntity;
import com.kryptokrauts.shared.dao.realtime.ListingBaseEntity;
import com.kryptokrauts.shared.dao.realtime.NotificationEntity;
import com.kryptokrauts.shared.dao.realtime.OpenListingBaseEntity;
import com.kryptokrauts.shared.dao.realtime.TransferEntity;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._Collection;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Notification;
import com.kryptokrauts.shared.model.realtime.notification._OfferNotification;
import com.kryptokrauts.shared.model.realtime.notification._RoyaltyDecreasedNotification;
import com.kryptokrauts.shared.model.realtime.notification._RoyaltyReceivedNotification;
import com.kryptokrauts.shared.model.realtime.notification._TransferNotification;
import jakarta.enterprise.context.ApplicationScoped;
import org.apache.commons.lang3.StringUtils;

@ApplicationScoped
public class NotificationTransformService {

  public _Notification toModel(NotificationEntity entity) {
    if (entity.getActionId() != null && StringUtils.isNotBlank(entity.getActionType())) {
      return switch (entity.getActionType()) {
        case "offer_declined" -> toOfferNotification(entity, true);
        case "offer_received" -> toOfferNotification(entity, false);
        case "offer_accepted" -> toOfferNotification(entity, false);
        case "auction_outbid" -> null;
        case "nft_received" -> toTransferNotification(entity);
        case "royalty_decreased" -> toRoyaltyDecreasedNotification(entity);
        case "royalty_received_listing" -> toRoyaltyReceivedNotification(entity, "listing");
        case "royalty_received_buyoffer" -> toRoyaltyReceivedNotification(entity, "buyoffer");
        case "royalty_received_auction" -> toRoyaltyReceivedNotification(entity, "auction");
        default -> null;
      };
    }
    return null;
  }

  private _OfferNotification toOfferNotification(
      NotificationEntity entity, boolean useDeclineMemo) {
    BuyofferBaseEntity buyoffer = BuyofferBaseEntity.findByBuyofferId(entity.getActionId());
    return _OfferNotification.builder()
        .acknowlegded(entity.getAcknowledged())
        .acknowlegdedDate(BaseMapper.mapDate(entity.getAcknowledgedDate()))
        .asset(AssetBaseEntity.toModel(buyoffer.getAssetId()))
        .bundleSize(buyoffer.getBundleSize())
        .buyer(BaseMapper.mapAccount(buyoffer.getBuyer()))
        .seller(BaseMapper.mapAccount(buyoffer.getSeller()))
        .collection(CollectionBaseView.toModel(buyoffer.getCollectionId()))
        .notificationId(entity.getId())
        .buyofferId(entity.getActionId())
        .price(buyoffer.getPrice().toModel())
        .receivedDate(BaseMapper.mapDate(entity.getBlockTimestamp()))
        .type(NotificationType.valueOf(entity.getActionType()))
        .message(useDeclineMemo ? buyoffer.getDeclineMemo() : buyoffer.getMemo())
        .build();
  }

  private _TransferNotification toTransferNotification(NotificationEntity entity) {
    TransferEntity transfer = TransferEntity.findByTransferId(entity.getActionId());
    return _TransferNotification.builder()
        .acknowlegded(entity.getAcknowledged())
        .acknowlegdedDate(BaseMapper.mapDate(entity.getAcknowledgedDate()))
        .asset(AssetBaseEntity.toModel(transfer.getPrimaryAssetId()))
        .bundle(transfer.getBundle())
        .from(BaseMapper.mapAccount(transfer.getSender()))
        .collection(CollectionBaseView.toModel(transfer.getCollectionId()))
        .notificationId(entity.getId())
        .transferId(transfer.getTransferId())
        .receivedDate(BaseMapper.mapDate(entity.getBlockTimestamp()))
        .type(NotificationType.nft_received)
        .build();
  }

  private _RoyaltyDecreasedNotification toRoyaltyDecreasedNotification(NotificationEntity entity) {
    OpenListingBaseEntity listing = OpenListingBaseEntity.findById(entity.getActionId());
    _Collection collection = CollectionBaseView.toModel(listing.getCollectionId());
    return _RoyaltyDecreasedNotification.builder()
        .acknowlegded(entity.getAcknowledged())
        .acknowlegdedDate(BaseMapper.mapDate(entity.getAcknowledgedDate()))
        .collection(collection)
        .notificationId(entity.getId())
        .receivedDate(BaseMapper.mapDate(entity.getBlockTimestamp()))
        .oldValue(listing.getListingRoyalty())
        .newValue(collection.getRoyalty())
        .type(NotificationType.royalty_decreased)
        .build();
  }

  private _RoyaltyReceivedNotification toRoyaltyReceivedNotification(
      NotificationEntity entity, String type) {
    _PriceInfo priceInfo = null;
    boolean bundle = false;
    CollectionBaseView collection = null;
    _Asset asset = null;
    if ("listing".equals(type)) {
      ListingBaseEntity listing = ListingBaseEntity.findByListingId(entity.getActionId());
      priceInfo =
          BaseMapper.buildPriceInfo(
              listing.getToken(), listing.getPrice(), listing.getCollectionFee());
      bundle = listing.getBundle();
      collection = CollectionBaseView.findById(listing.getCollectionId());
      asset = AssetBaseEntity.toModel(listing.getPrimaryAssetId());
    } else if ("buyoffer".equals(type)) {
      BuyofferBaseEntity buyoffer = BuyofferBaseEntity.findByBuyofferId(entity.getActionId());
      priceInfo = buyoffer.getPrice().toModel();
      bundle = buyoffer.getBundle();
      collection = CollectionBaseView.findById(buyoffer.getCollectionId());
      asset = AssetBaseEntity.toModel(buyoffer.getAssetId());
    } else if ("auction".equals(type)) {
      AuctionBaseEntity auction = AuctionBaseEntity.findByAuctionId(entity.getActionId());
      priceInfo =
          BaseMapper.buildPriceInfo(
              auction.getAuctionToken(),
              auction.getAuctionCurrentBid(),
              auction.getAuctionRoyalty());
      bundle = auction.getBundle();
      collection = CollectionBaseView.findById(auction.getCollectionId());
      asset = AssetBaseEntity.toModel(auction.getAssetId());
    }

    return _RoyaltyReceivedNotification.builder()
        .acknowlegded(entity.getAcknowledged())
        .acknowlegdedDate(BaseMapper.mapDate(entity.getAcknowledgedDate()))
        .collection(collection.toModel())
        .asset(asset)
        .notificationId(entity.getId())
        .receivedDate(BaseMapper.mapDate(entity.getBlockTimestamp()))
        .bundle(bundle)
        .royaltyAmount(priceInfo)
        .type(NotificationType.royalty_received)
        .marketType(type)
        .build();
  }
}

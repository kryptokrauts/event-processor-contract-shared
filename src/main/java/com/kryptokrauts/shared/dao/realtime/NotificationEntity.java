package com.kryptokrauts.shared.dao.realtime;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.contract.types.NotificationType;
import com.kryptokrauts.shared.dao.common.AssetBaseEntity;
import com.kryptokrauts.shared.dao.common.CollectionBaseView;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._Collection;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Notification;
import com.kryptokrauts.shared.model.realtime.notification._OfferNotification;
import com.kryptokrauts.shared.model.realtime.notification._RoyaltyDecreasedNotification;
import com.kryptokrauts.shared.model.realtime.notification._RoyaltyReceivedNotification;
import com.kryptokrauts.shared.model.realtime.notification._TransferNotification;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import org.apache.commons.lang3.StringUtils;

@Getter
@Entity
@Table(name = "soonmarket_notification")
public class NotificationEntity extends PanacheEntityBase {

  @Id private Long globalSequence;

  @Id private String actionType;

  @Id private String account;

  private Long id;

  private Long blockTimestamp;

  private Long actionId;

  private Boolean acknowledged;

  private Long acknowledgedDate;

  public _Notification toModel() {
    if (id != null && StringUtils.isNotBlank(actionType)) {
      return switch (actionType) {
        case "offer_declined" -> toOfferNotification(true);
        case "offer_received" -> toOfferNotification(false);
        case "offer_accepted" -> toOfferNotification(false);
        case "auction_outbid" -> null;
        case "nft_received" -> toTransferNotification();
        case "royalty_decreased" -> toRoyaltyDecreasedNotification();
        case "royalty_received_listing" -> toRoyaltyReceivedNotification("listing");
        case "royalty_received_buyoffer" -> toRoyaltyReceivedNotification("buyoffer");
        case "royalty_received_auction" -> toRoyaltyReceivedNotification("auction");
        default -> null;
      };
    }
    return null;
  }

  private _OfferNotification toOfferNotification(boolean useDeclineMemo) {
    BuyofferBaseEntity buyoffer = BuyofferBaseEntity.findByBuyofferId(actionId);
    return _OfferNotification.builder()
        .acknowlegded(acknowledged)
        .acknowlegdedDate(BaseMapper.mapDate(acknowledgedDate))
        .asset(AssetBaseEntity.toModel(buyoffer.getAssetId()))
        .bundleSize(buyoffer.getBundleSize())
        .buyer(BaseMapper.mapAccount(buyoffer.getBuyer()))
        .seller(BaseMapper.mapAccount(buyoffer.getSeller()))
        .collection(CollectionBaseView.toModel(buyoffer.getCollectionId()))
        .notificationId(id)
        .buyofferId(actionId)
        .price(buyoffer.getPrice().toModel())
        .receivedDate(BaseMapper.mapDate(blockTimestamp))
        .type(NotificationType.valueOf(actionType))
        .message(useDeclineMemo ? buyoffer.getDeclineMemo() : buyoffer.getMemo())
        .build();
  }

  private _TransferNotification toTransferNotification() {
    TransferEntity transfer = TransferEntity.findByTransferId(actionId);
    return _TransferNotification.builder()
        .acknowlegded(acknowledged)
        .acknowlegdedDate(BaseMapper.mapDate(acknowledgedDate))
        .asset(AssetBaseEntity.toModel(transfer.getPrimaryAssetId()))
        .bundle(transfer.getBundle())
        .from(BaseMapper.mapAccount(transfer.getSender()))
        .collection(CollectionBaseView.toModel(transfer.getCollectionId()))
        .notificationId(id)
        .transferId(transfer.getTransferId())
        .receivedDate(BaseMapper.mapDate(blockTimestamp))
        .type(NotificationType.nft_received)
        .build();
  }

  private _RoyaltyDecreasedNotification toRoyaltyDecreasedNotification() {
    OpenListingBaseEntity listing = OpenListingBaseEntity.findById(actionId);
    _Collection collection = CollectionBaseView.toModel(listing.getCollectionId());
    return _RoyaltyDecreasedNotification.builder()
        .acknowlegded(acknowledged)
        .acknowlegdedDate(BaseMapper.mapDate(acknowledgedDate))
        .collection(collection)
        .notificationId(id)
        .receivedDate(BaseMapper.mapDate(blockTimestamp))
        .oldValue(listing.getListingRoyalty())
        .newValue(collection.getRoyalty())
        .type(NotificationType.royalty_decreased)
        .build();
  }

  private _RoyaltyReceivedNotification toRoyaltyReceivedNotification(String type) {
    _PriceInfo priceInfo = null;
    boolean bundle = false;
    CollectionBaseView collection = null;
    _Asset asset = null;
    if ("listing".equals(type)) {
      ListingBaseEntity listing = ListingBaseEntity.findByListingId(actionId);
      priceInfo =
          BaseMapper.buildPriceInfo(
              listing.getToken(), listing.getPrice(), listing.getCollectionFee());
      bundle = listing.getBundle();
      collection = CollectionBaseView.findById(listing.getCollectionId());
      asset = AssetBaseEntity.toModel(listing.getPrimaryAssetId());
    } else if ("buyoffer".equals(type)) {
      BuyofferBaseEntity buyoffer = BuyofferBaseEntity.findByBuyofferId(actionId);
      priceInfo = buyoffer.getPrice().toModel();
      bundle = buyoffer.getBundle();
      collection = CollectionBaseView.findById(buyoffer.getCollectionId());
      asset = AssetBaseEntity.toModel(buyoffer.getAssetId());
    } else if ("auction".equals(type)) {
      AuctionBaseEntity auction = AuctionBaseEntity.findByAuctionId(actionId);
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
        .acknowlegded(acknowledged)
        .acknowlegdedDate(BaseMapper.mapDate(acknowledgedDate))
        .collection(collection.toModel())
        .asset(asset)
        .notificationId(id)
        .receivedDate(BaseMapper.mapDate(blockTimestamp))
        .bundle(bundle)
        .royaltyAmount(priceInfo)
        .type(NotificationType.royalty_received)
        .marketType(type)
        .build();
  }
}

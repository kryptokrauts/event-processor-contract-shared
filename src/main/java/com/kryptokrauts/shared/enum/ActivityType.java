package com.kryptokrauts.soonmarket.api.realtime.schema;

public enum ActivityType {
  collection_created,
  royalties_updated,
  mint,
  transfer,
  burn,
  listing_created,
  listing_cancelled,
  purchase,
  auction_started,
  auction_bid,
  auction_ended,
  auction_cancelled,
  offer_created,
  offer_revoked,
  offer_declined,
  offer_accepted,
  otc_offer_created,
  otc_offer_revoked,
  otc_offer_declined,
  otc_offer_accepted,
  unknown;
}

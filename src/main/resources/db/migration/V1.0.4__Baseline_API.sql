
----------------------------------
-- Buyoffer
----------------------------------

CREATE OR REPLACE VIEW soonmarket_buyoffer_open_v AS
SELECT 
	gen_random_uuid() AS id,
	t1.blocknum AS blocknum, 
	t1.block_timestamp AS buyoffer_date,
	t1.buyoffer_id,
	t1.primary_asset_id,
	t2.asset_id,
	t2.template_id,
	t5.collection_id,
	t4.serial,
	t4.edition_size,
	t4.asset_name,
	t4.asset_media,
	t4.asset_media_type,
	t4.asset_media_preview,
	t4.owner,
	t5.name AS collection_name,
	t1.seller,
	t1.buyer,
	t1.bundle,
	t1.token,
	t1.price,
	t1.memo,
	t1.collection_fee AS royalty,
	0.02::DOUBLE PRECISION AS market_fee
FROM (SELECT * FROM atomicmarket_buyoffer b WHERE NOT EXISTS (SELECT 1 FROM atomicmarket_buyoffer_state WHERE b.buyoffer_id=buyoffer_id)) t1
LEFT JOIN atomicmarket_buyoffer_asset t2 ON t1.buyoffer_id=t2.buyoffer_id
LEFT JOIN soonmarket_asset_base_v t4 ON t2.asset_id=t4.asset_id
LEFT JOIN soonmarket_collection_v t5 ON t4.collection_id = t5.collection_id;

COMMENT ON VIEW soonmarket_buyoffer_open_v IS 'Get open buyoffers for given asset or template';

----------------------------------
-- NFT Card View
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_nft_card
(
    blocknum bigint,
    block_timestamp bigint,
		_card_state text,
		_card_quick_action text,
    asset_id bigint,
		mint_date bigint,
    serial bigint,
    transferable boolean,
    burnable boolean,
    edition_size bigint,
    template_id bigint,
    schema_id text ,
    collection_id text ,
    asset_name text ,
    asset_media text ,
    asset_media_type text ,
    asset_media_preview text ,
    owner text ,
    collection_name text ,
    collection_image text ,
    royalty double precision,
    creator text ,
    has_kyc boolean,
    shielded boolean,
    blacklisted boolean,
    num_auctions integer,
    num_listings integer,
    num_bundles integer,
    has_offers boolean,    
    last_sold_for_price double precision,
    last_sold_for_token text,
    last_sold_for_price_usd numeric,
    last_sold_for_royalty_usd numeric,
    last_sold_for_market_fee_usd numeric,    
    listing_id bigint,
    listing_price double precision,
    listing_price_usd numeric,
    listing_token text ,
    listing_royalty double precision,
    listing_market_fee numeric,
    listing_date bigint,
    listing_seller text ,
    bundle boolean,
    bundle_index integer,
    bundle_size integer,
    auction_id bigint,
    auction_seller TEXT,
    auction_royalty double precision,
    auction_token TEXT,
    auction_starting_bid double precision,
    auction_current_bid double precision,
    num_bids integer,
    highest_bidder TEXT,
    auction_start_date bigint,
    auction_end_date bigint,
    display boolean
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_asset_id
    ON public.soonmarket_nft_card USING btree
    (asset_id DESC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_template_id
    ON public.soonmarket_nft_card USING btree
    (template_id DESC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_collection_id
    ON public.soonmarket_nft_card USING btree
    (collection_id)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_has_kyc
    ON public.soonmarket_nft_card USING btree
    (has_kyc)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_has_offers
    ON public.soonmarket_nft_card USING btree
    (has_offers)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_bundle
    ON public.soonmarket_nft_card USING btree
    (bundle)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_blacklisted
    ON public.soonmarket_nft_card USING btree
    (blacklisted)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_auction_token
    ON public.soonmarket_nft_card USING btree
    (auction_token)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_auction_end_date
    ON public.soonmarket_nft_card USING btree
    (auction_end_date)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_listing_token
    ON public.soonmarket_nft_card USING btree
    (listing_token)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_listing_date
    ON public.soonmarket_nft_card USING btree
    (listing_date)
    TABLESPACE pg_default;					

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_mint_date
    ON public.soonmarket_nft_card USING btree
    (mint_date)
    TABLESPACE pg_default;			

--

CREATE OR REPLACE VIEW soonmarket_nft_card_v AS
SELECT t1.*,ABS(FLOOR((extract(epoch from NOW() at time zone 'utc'))*1000) - 
CASE 
	WHEN t1.auction_id IS NOT NULL THEN t1.auction_end_date 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_date
	ELSE t1.block_timestamp END 
) AS sort_date,
round_to_decimals_f(CASE 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_price 
	WHEN t1.auction_id IS NOT null THEN COALESCE(t1.auction_current_bid,t1.auction_starting_bid)
	END * e.usd)
	AS filter_price_usd
FROM soonmarket_nft_card t1
LEFT JOIN soonmarket_exchange_rate_latest_v e ON e.token_symbol = 
CASE 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_token
	WHEN t1.auction_id IS NOT NULL THEN t1.auction_token
END
WHERE NOT blacklisted AND (CASE WHEN auction_end_date IS NOT NULL THEN FLOOR((extract(epoch from NOW() at time zone 'utc'))*1000) <= t1.auction_end_date ELSE TRUE END);

COMMENT ON VIEW soonmarket_nft_card_v IS 'View for NFT Cards';

----------------------------------
-- NFT Detail View
----------------------------------

CREATE OR REPLACE VIEW soonmarket_nft_detail_v AS
	SELECT
	t1.*,
	t2.listing_id,
	t3.auction_id
FROM soonmarket_asset_v t1
LEFT JOIN (select max(listing_id) AS listing_id,asset_id from soonmarket_listing_v t2 where not bundle GROUP BY asset_id and state is null)t2 ON t1.asset_id=t2.asset_id AND NOT t1.burned
LEFT JOIN (select max(auction_Id) as auction_id,asset_id from soonmarket_auction_v t3 where active group by asset_id)t3 ON t1.asset_id=t3.asset_id AND NOT t1.burned;

COMMENT ON VIEW soonmarket_nft_detail_v IS 'View for NFT Details';

-----------------------------------------
-- MyNFTs View
-----------------------------------------

CREATE VIEW soonmarket_my_nfts_v as
SELECT 
	t1.asset_id, 
	t2.template_id,
	t2.serial,
	t4.edition_size,
	t2.block_timestamp AS mint_date, 
	t1.block_timestamp AS received_date, 
	burned,	
	CASE WHEN burned THEN t1.block_timestamp ELSE NULL END AS burned_date,
	COALESCE(t3.name,t4.name) AS asset_name,
	COALESCE(t3.media,t4.media) AS asset_media,
	COALESCE(t3.media_type,t4.media_type) AS asset_media_type,
	COALESCE(t3.media_preview,t4.media_preview) AS asset_media_preview, 	
	COALESCE(t3.transferable,t4.transferable) AS transferable,	
	COALESCE(t3.burnable,t4.burnable) AS burnable,
	t1.owner,
	t2.collection_id,
	t5.name AS collection_name,
	t5.image AS collection_image,
	t5.creator,
	t5.shielded,
	t5.blacklisted,
	t5.blacklist_date,
	t5.blacklist_reason,
	t5.blacklist_actor,
	t7.auction_id,
	t7.auction_end AS auction_end_time,
	t7.token as auction_token,
	t7.starting_price as auction_starting_bid,
	t7.current_bid as auction_current_bid,
	COALESCE(t7.bundle,t8.bundle,false) AS bundle,
	t8.listing_id,
	t8.listing_date,
	t8.listing_token,
	t8.listing_price,
	t9.price,
	t9.token,
	COALESCE(COALESCE(t7.current_bid,t7.starting_price),t8.listing_price) AS filter_price_usd
FROM atomicassets_asset_owner_log t1
inner JOIN atomicassets_asset t2 ON t1.asset_id=t2.asset_id
LEFT JOIN atomicassets_asset_data t3 ON t1.asset_id=t3.asset_id
LEFT JOIN soonmarket_template_v t4 ON t2.template_id=t4.template_id
LEFT JOIN soonmarket_collection_v t5 on t2.collection_id=t5.collection_id
left JOIN LATERAL (SELECT auction_id,auction_end,token,starting_price,current_bid,bundle from soonmarket_auction_base_v where t1.asset_id=asset_id AND active) t7 ON true
left JOIN LATERAL (SELECT listing_id,listing_date,listing_token,listing_price,bundle from soonmarket_listing_valid_mv where t1.asset_id=asset_id)t8 ON true
LEFT JOIN soonmarket_last_sold_for_asset_v t9 ON t1.asset_id=t9.asset_id AND buyer=OWNER
WHERE t1.CURRENT AND NOT blacklisted

COMMENT ON VIEW soonmarket_my_nfts_v IS 'View for MyNFTs';

-----------------------------------------
-- Manage NFTs View
-----------------------------------------

CREATE OR replace VIEW soonmarket_manageable_nft_v as
SELECT * FROM(
SELECT 
t1.minted - t1.burned AS num_circulating,
t1.burned AS num_burned,
t1.mintable AS num_mintable,
t1.last_minting_date,
t2.*
FROM (
	SELECT 
		creator,
		template_id,
	   edition_size AS total,
		COUNT(*) AS minted,
		count(CASE WHEN burned THEN 1 end) AS burned,
		CASE WHEN edition_size != 0 THEN edition_size - COUNT(*) ELSE 0 END AS mintable,
		MAX(t1.mint_date) AS last_minting_date
	FROM soonmarket_nft t1
	WHERE edition_size != 1
	GROUP BY template_id,edition_size,creator) t1
LEFT JOIN LATERAL (SELECT * from soonmarket_nft WHERE t1.template_id=template_id AND t1.creator=creator AND edition_size!=1 LIMIT 1)t2 ON TRUE
UNION ALL
SELECT NULL,NULL,NULL,NULL, * FROM soonmarket_nft WHERE edition_size=1)t

----------------------------------
-- Collection Detail View
----------------------------------

CREATE VIEW soonmarket_collection_detail_v AS
SELECT                                                                            
t1.collection_id,                                                                 
t1.creator,                                                                       
t3.royalty as collection_fee,                                                                       
t2.category,                                                                      
t2.image,          
(SELECT COUNT(*) FROM atomicassets_asset WHERE collection_id=t1.collection_id) AS num_nfts,
(SELECT COUNT(DISTINCT owner) FROM soonmarket_asset_base_v WHERE collection_id=t1.collection_id) AS num_holders,
(SELECT COUNT(*) FROM soonmarket_listing_v v WHERE v.collection_id=t1.collection_id AND VALID and STATE is null) AS num_listings,
(SELECT COUNT(*) FROM atomicmarket_sale sl1 inner join atomicmarket_sale_state sl2 ON sl1.sale_id=sl2.sale_id WHERE sl1.collection_id=t1.collection_id AND STATE=3) AS total_sales,
0 AS num_stars,
0 AS totalVolumeUSD,
DATA ->> 'url' AS socials,
/* REFRESH MATERIALIZED VIEW CONCURRENTLY!
(
	SELECT
		sum(her.usd*price) 
	FROM
	(
		SELECT sl.listing_price AS price,sl.listing_date AS utc_date, listing_token AS token FROM soonmarket_listing_v sl WHERE sl.collection_id=t1.collection_id AND STATE=3 
		UNION ALL
		SELECT sl.auction_current_bid,sl.auction_end_date, auction_token FROM soonmarket_auction_v sl WHERE sl.collection_id=t1.collection_id AND STATE=3 
		UNION ALL
		SELECT sl.auction_current_bid,sl.auction_end_date, auction_token FROM atomicmarket_buyoffer_state sl WHERE sl.collection_id=t1.collection_id AND STATE=3 
	)vol	
	LEFT JOIN soonmarket_exchange_rate_historic_v her ON
	her.utc_date=get_utc_date_f(vol.utc_date) 
	AND her.token_symbol=vol.token
) AS total_volume_usd,
*/
'' AS top_holders,
(SELECT string_agg(SCHEMA_NAME,',') FROM atomicassets_schema sc WHERE sc.collection_id=t1.collection_id GROUP BY sc.collection_id) AS schemes,
DATA ->> 'banner' AS banner,
(SELECT listing_token FROM soonmarket_listing_v sl,soonmarket_exchange_rate_latest_v er WHERE sl.collection_id=t1.collection_id AND er.token_symbol=sl.listing_token AND NOT bundle AND VALID AND STATE IS null ORDER BY (listing_price*er.usd) ASC LIMIT 1) AS floor_price_token,
(SELECT listing_price FROM soonmarket_listing_v sl,soonmarket_exchange_rate_latest_v er WHERE sl.collection_id=t1.collection_id AND er.token_symbol=sl.listing_token AND NOT bundle AND VALID AND STATE IS null ORDER BY (listing_price*er.usd) ASC LIMIT 1) AS floor_price,
(SELECT token FROM soonmarket_buyoffer_open_v bo,soonmarket_exchange_rate_latest_v er WHERE bo.collection_id=t1.collection_id AND er.token_symbol=bo.token AND NOT bundle ORDER BY (price*er.usd) DESC LIMIT 1) AS top_offer_token,
(SELECT price FROM soonmarket_buyoffer_open_v bo,soonmarket_exchange_rate_latest_v er WHERE bo.collection_id=t1.collection_id AND er.token_symbol=bo.token AND NOT bundle ORDER BY (price*er.usd) DESC LIMIT 1) AS top_offer_price,
CASE WHEN b1.collection_id IS NOT NULL or b2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS blacklisted,
COALESCE(b1.block_timestamp,b2.block_timestamp) AS blacklist_date,
COALESCE(b1.reporter_comment,b2.reporter_comment) AS blacklist_reason,
CASE WHEN b1.reporter is not null THEN 'NFT Watch' WHEN b2.reporter is not null THEN 'Soon.Market' ELSE null END AS blacklist_actor,
CASE WHEN s1.collection_id IS NOT NULL or s2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS shielded,
t2.name,                                                                          
t2.description
FROM atomicassets_collection t1                                                   
LEFT JOIN atomicassets_collection_data_log t2 ON t1.collection_id = t2.collection_id and t2.current
LEFT JOIN atomicassets_collection_royalty_log t3 ON t1.collection_id = t3.collection_id and t3.current
LEFT JOIN nft_watch_blacklist b1 ON t1.collection_id = b1.collection_id           
LEFT JOIN soonmarket_internal_blacklist b2 ON t1.collection_id = b2.collection_id 
LEFT JOIN nft_watch_shielding s1 ON t1.collection_id = s1.collection_id           
LEFT JOIN soonmarket_internal_shielding s2 ON t1.collection_id = s2.collection_id;

----------------------------------
-- Edition
----------------------------------

CREATE VIEW soonmarket_edition_auctions_v as
SELECT 
	*
FROM soonmarket_auction_v
WHERE active
ORDER BY SERIAL asc;

COMMENT ON VIEW soonmarket_edition_auctions_v IS 'Get all auctions for a given edition/template';

--

CREATE OR REPLACE VIEW soonmarket_edition_listings_v AS
	SELECT 
	asset_id,
	template_id,
	SERIAL,
	listing_id,
	listing_date,
	seller,
	listing_token,
	listing_price,
	listing_royalty,
	bundle_size
FROM soonmarket_listing_v listings WHERE VALID AND STATE IS NULL 
ORDER BY SERIAL asc;

COMMENT ON VIEW soonmarket_edition_listings_v IS 'Get all listings for a given edition/template';

--

CREATE OR REPLACE VIEW soonmarket_edition_bundles_v AS
SELECT 
	asset_id,
	SERIAL,
	template_id,
	bundle_size,
	seller,
	listing_id,
   listing_date,
   listing_token,
   listing_price,
   listing_royalty,    
	NULL as auction_id,
	NULL as auction_start_date,
	NULL as auction_end_date,
	NULL as auction_token,
	NULL as auction_starting_bid,
	NULL as auction_royalty,
	NULL as auction_current_bid,
	NULL as num_bids,
	NULL as highest_bidder
FROM soonmarket_edition_listings_v WHERE bundle_size IS NOT NULL
UNION 
SELECT 
	asset_id,
	SERIAL,
	template_id,
	bundle_size,
	seller,
	NULL as _id,
	NULL as _date,
	NULL as _token,
	NULL as _price,
	NULL as _royalty,
	auction_id,
	auction_start_date,
	auction_end_date,
	auction_token,
	auction_starting_bid,
	auction_royalty,
	auction_current_bid,
	num_bids,
	highest_bidder
FROM soonmarket_edition_auctions_v WHERE bundle_size IS NOT NULL;

COMMENT ON VIEW soonmarket_edition_listings_v IS 'Get all bundles for a given edition/template';

--

CREATE OR REPLACE VIEW soonmarket_edition_info_v as
 SELECT t1.asset_id,
    t1.template_id,
    t1.serial,
    t1.owner,
        CASE
            WHEN t1.burned THEN 'burned'
            WHEN (t3.auction_id IS NOT NULL) THEN 'auction'
            WHEN (t2.listing_id IS NOT NULL) THEN 'listed'
            ELSE 'unlisted'
        END AS state,
    COALESCE(t3.auction_token, t2.listing_token) AS token,
    COALESCE(COALESCE(t3.auction_current_bid, t3.auction_starting_bid), t2.listing_price) AS price,
    COALESCE(t3.auction_royalty, t2.listing_royalty) AS royalty
   FROM soonmarket_asset_base_v t1
     LEFT JOIN soonmarket_listing_v t2 ON t1.asset_id = t2.asset_id AND t2.valid AND STATE is null AND t2.bundle != true
   LEFT JOIN soonmarket_auction_v t3 ON t1.asset_id = t3.asset_id AND t3.active AND t3.bundle != true;
 
COMMENT ON VIEW soonmarket_edition_info_v IS 'Get serial info for a template';

----------------------------------
-- Auction
----------------------------------

CREATE OR REPLACE VIEW soonmarket_auction_bids_v AS
SELECT 
	t1.auction_id,
	t1.block_timestamp AS bid_date,
	t1.current_bid,
	t2.collection_fee AS royalty,
	t2.token,
	t1.bidder,
	t1.updated_end_time,
	t1.bid_number
FROM atomicmarket_event_auction_bid_log t1
LEFT JOIN atomicmarket_auction t2 ON t1.auction_id=t2.auction_id
ORDER BY t1.bid_number;

COMMENT ON VIEW soonmarket_auction_bids_v IS 'Get done auction bids';

----------------------------------
-- Collection Holder
----------------------------------

CREATE OR replace VIEW soonmarket_collection_holder_v AS
WITH collection_owner AS (
	SELECT 
	COALESCE(t1.owner,t2.receiver) AS account,
	t2.collection_id
	FROM atomicassets_asset t2
	LEFT JOIN atomicassets_asset_owner_log t1 ON t1.asset_id=t2.asset_id AND current AND NOT burned
)
SELECT	
	account,
	collection_id,
	COUNT(*) AS num_nfts,
	0 as num_bought,
	0 AS owned
FROM collection_owner
GROUP BY collection_id, account
ORDER BY num_nfts DESC;

COMMENT ON VIEW soonmarket_collection_holder_v IS 'List of collection holders and stats';

----------------------------------
-- Profile
----------------------------------

CREATE VIEW soonmarket_asset_owner_v AS 
SELECT 
COALESCE(t1.owner,t2.receiver) as owner,
t1.asset_id,
t2.template_id,
t2.collection_id
FROM atomicassets_asset_owner_log t1 
LEFT JOIN atomicassets_asset t2 ON t1.asset_id=t2.asset_id 
WHERE t1.current AND NOT t1.burned;

--

CREATE OR replace VIEW soonmarket_profile_v as
SELECT 
	t1.*,
	(SELECT COUNT(*) FROM soonmarket_asset_owner_v t2 WHERE t2.owner=t1.account ) AS num_nfts,
	(SELECT COUNT(*) FROM soonmarket_listing_v t2 WHERE STATE=3 AND t2.buyer=t1.account) AS num_bought,
	(SELECT MAX(t2.listing_date) FROM soonmarket_listing_v t2 WHERE STATE=3 AND t2.buyer=t1.account) AS last_bought,
	(SELECT COUNT(*) FROM soonmarket_listing_v t2 WHERE STATE=3 AND t2.seller=t1.account) AS num_sold,
	(SELECT MAX(t2.listing_date) FROM soonmarket_listing_v t2 WHERE STATE=3 AND t2.seller=t1.account) AS last_sold
FROM soonmarket_profile t1;
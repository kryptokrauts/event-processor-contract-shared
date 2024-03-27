
----------------------------------
-- Buyoffer
----------------------------------

CREATE OR REPLACE VIEW soonmarket_buyoffer_open_v AS
WITH config as (
SELECT maker_fee+taker_fee as market_fee FROM atomicmarket_config ORDER BY id DESC LIMIT 1	
),
valid_offers AS (
SELECT 
	t1.buyoffer_id,
	BOOL_AND(COALESCE(t4.owner = t1.seller,FALSE)) AS VALID,
	BOOL_OR(burned) AS burned
FROM atomicmarket_buyoffer t1 
INNER JOIN atomicmarket_buyoffer_asset t3 ON t1.buyoffer_id=t3.buyoffer_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t3.asset_id=t4.asset_id AND t4.current
WHERE NOT EXISTS(SELECT 1 from atomicmarket_buyoffer_state t2 where t1.buyoffer_id=t2.buyoffer_id)
GROUP BY t1.buyoffer_id
)
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
	config.market_fee,
	t5.shielded
FROM config, valid_offers v
LEFT JOIN atomicmarket_buyoffer t1 ON v.buyoffer_id = t1.buyoffer_id
LEFT JOIN atomicmarket_buyoffer_asset t2 ON t1.buyoffer_id=t2.buyoffer_id
LEFT JOIN soonmarket_asset_base_v t4 ON t2.asset_id=t4.asset_id
LEFT JOIN soonmarket_collection_v t5 ON t4.collection_id = t5.collection_id
WHERE v.valid AND NOT v.burned;

COMMENT ON VIEW soonmarket_buyoffer_open_v IS 'Get open buyoffers for given asset or template';

--

CREATE OR REPLACE VIEW soonmarket_my_offers_v AS
SELECT 
	t1.blocknum AS blocknum, 
	t1.block_timestamp AS buyoffer_date,
	t1.buyoffer_id,
	t1.primary_asset_id AS asset_id,
	t4.template_id,
	t4.serial,
	t4.edition_size,
	t4.asset_name,
	t4.asset_media,
	t4.asset_media_type,
	t4.asset_media_preview,
	t4.owner,
	t5.collection_id,
	t5.name AS collection_name,
	t5.image as collection_image,
	t5.creator,
	t1.seller,
	t1.buyer,
	t1.bundle,
	t1.bundle_size,
	t1.token,
	t1.price,
	t1.memo,
	t1.collection_fee AS royalty,
	t5.shielded
FROM (SELECT * FROM atomicmarket_buyoffer b WHERE NOT EXISTS (SELECT 1 FROM atomicmarket_buyoffer_state WHERE b.buyoffer_id=buyoffer_id)) t1
LEFT JOIN soonmarket_asset_base_v t4 ON t1.primary_asset_id=t4.asset_id
LEFT JOIN soonmarket_collection_v t5 ON t4.collection_id = t5.collection_id;

COMMENT ON VIEW soonmarket_my_offers_v IS 'Get my open buyoffers for given asset or template';

----------------------------------
-- NFT Card View
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_nft_card
(
		id bigserial PRIMARY KEY,
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
    listing_token text ,
    listing_royalty double precision,
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

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_listing_id
    ON public.soonmarket_nft_card USING btree
    (listing_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_auction_id
    ON public.soonmarket_nft_card USING btree
    (auction_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_card_edition_size
    ON public.soonmarket_nft_card USING btree
    (edition_size)
    TABLESPACE pg_default;								

--

CREATE OR REPLACE VIEW soonmarket_nft_card_v AS
SELECT t1.*,
ABS(FLOOR((extract(epoch from NOW() at time zone 'utc'))*1000) - 
CASE 
	WHEN t1.auction_id IS NOT NULL THEN t1.auction_end_date 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_date
	ELSE t1.mint_date END 
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
LEFT JOIN (select max(listing_id) AS listing_id,asset_id from soonmarket_listing_valid_v t2 where not bundle GROUP BY asset_id)t2 ON t1.asset_id=t2.asset_id AND NOT t1.burned
LEFT JOIN (select max(auction_Id) as auction_id,asset_id from soonmarket_auction_v t3 where active group by asset_id)t3 ON t1.asset_id=t3.asset_id AND NOT t1.burned;

COMMENT ON VIEW soonmarket_nft_detail_v IS 'View for NFT Details';

-----------------------------------------
-- MyNFTs Table
-----------------------------------------

WITH asset_owner AS(
SELECT 
	t1.blocknum,
	t1.block_timestamp,
	t1.asset_id, 
	t1.template_id,
	t1.schema_id,
	t1.collection_id,	
	t1.serial,
	t4.edition_size,
	COALESCE(t3.transferable,t4.transferable) AS transferable,	
	COALESCE(t3.burnable,t4.burnable) AS burnable,	
	t2.owner,
	t2.block_timestamp AS mint_date, 
	COALESCE(t2.block_timestamp,t1.block_timestamp) AS received_date, 			
	COALESCE(burned,FALSE) AS burned,
	CASE WHEN burned THEN t1.block_timestamp ELSE NULL END AS burned_date,
	CASE WHEN burned THEN t2.owner END AS burned_by,
	COALESCE(t3.name,t4.name) AS asset_name,
	COALESCE(t3.media,t4.media) AS asset_media,
	COALESCE(t3.media_type,t4.media_type) AS asset_media_type,
	COALESCE(t3.media_preview,t4.media_preview) AS asset_media_preview, 	
	t5.name AS collection_name,
	t5.image AS collection_image,
	t5.collection_fee AS royalty,
	t5.creator,
	t6.has_kyc,
	t5.shielded
FROM atomicassets_asset t1
LEFT JOIN atomicassets_asset_owner_log t2 ON t1.asset_id=t2.asset_id AND t2.current 
LEFT JOIN atomicassets_asset_data t3 ON t1.asset_id=t3.asset_id
LEFT JOIN soonmarket_template_v t4 ON t1.template_id=t4.template_id
LEFT JOIN soonmarket_collection_v t5 ON t1.collection_id=t5.collection_id
LEFT JOIN soonmarket_profile t6 ON t5.creator=t6.account	
where not blacklisted
)
SELECT 
	t1.*,
	t10.asset_id is not null as has_offers,
	t9.price as last_sold_for_price,
  t9.token as last_sold_for_token,
	t9.price * t11.usd as last_sold_for_price_usd,
	t9.price * t9.royalty * t11.usd as last_sold_for_royalty_usd,
	t9.price * (t9.maker_market_fee+t9.taker_market_fee) * t11.usd as last_sold_for_market_fee_usd,
	t9.bundle as last_sold_for_bundle,
	t7.auction_id,
	t7.auction_end AS auction_end_date,
	t7.token as auction_token,
	t7.starting_price as auction_starting_bid,
	t7.current_bid as auction_current_bid,
	t7.collection_fee AS auction_royalty,	
	t7.num_bids,
	COALESCE(t7.bundle,t8.bundle,false) AS bundle,
	COALESCE(t7.bundle_size,t8.bundle_size,null) AS bundle_size,		
	t8.listing_id,
	t8.listing_date,
	t8.listing_token,
	t8.listing_price,
	t8.listing_royalty
INTO soonmarket_nft
FROM asset_owner t1
left JOIN soonmarket_auction_base_v t7 ON t1.asset_id=t7.asset_id AND active 
left JOIN soonmarket_listing_valid_v t8 on t1.asset_id=t8.asset_id  
LEFT JOIN soonmarket_last_sold_for_asset_v t9 ON t1.asset_id=t9.asset_id
LEFT JOIN soonmarket_exchange_rate_historic_v t11
	ON t9.token=t11.token_symbol 
	AND TO_CHAR(TO_TIMESTAMP(t9.block_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00') = t11.utc_date
LEFT JOIN LATERAL (select asset_id from soonmarket_buyoffer_open_v where t1.asset_id=asset_id limit 1)t10 ON true;

ALTER TABLE soonmarket_nft ADD COLUMN id bigserial;
ALTER TABLE soonmarket_nft ADD CONSTRAINT pk_soonmarket_nft PRIMARY KEY (id);

COMMENT ON TABLE soonmarket_nft IS 'Base NFT table';

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_burned_creator
    ON public.soonmarket_nft USING btree
    (burned,creator)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_owner_transferable
    ON public.soonmarket_nft USING btree
    (owner,transferable)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_templateid_creator_editionsize
    ON public.soonmarket_nft USING btree
    (template_id,creator,edition_size)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_burned_owner
    ON public.soonmarket_nft USING btree
    (burned,owner)
    TABLESPACE pg_default;				

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_editionsize
    ON public.soonmarket_nft USING btree
    (edition_size)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_burnable
    ON public.soonmarket_nft USING btree
    (burnable)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_shielded
    ON public.soonmarket_nft USING btree
    (shielded)
    TABLESPACE pg_default;			

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_has_offers
    ON public.soonmarket_nft USING btree
    (has_offers)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_kyced
    ON public.soonmarket_nft USING btree
    (has_kyc)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_listing_date
    ON public.soonmarket_nft USING btree
    (listing_date)
    TABLESPACE pg_default;
	
CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_auction_end_date
    ON public.soonmarket_nft USING btree
    (auction_end_date)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_nft_mint_date
    ON public.soonmarket_nft USING btree
    (mint_date)
    TABLESPACE pg_default;		
		
CREATE INDEX IF NOT EXISTS idx_soonmarket_asset_id
    ON public.soonmarket_nft USING btree
    (asset_id)
    TABLESPACE pg_default;	
	
CREATE INDEX IF NOT EXISTS idx_soonmarket_template_id
    ON public.soonmarket_nft USING btree
    (template_id)
    TABLESPACE pg_default;
	
CREATE INDEX IF NOT EXISTS idx_soonmarket_collection_id
    ON public.soonmarket_nft USING btree
    (collection_id)
    TABLESPACE pg_default;										

----------------------------------
-- MyNFTs View
----------------------------------

CREATE OR REPLACE VIEW soonmarket_nft_v AS
SELECT t1.*,
ABS(FLOOR((extract(epoch from NOW() at time zone 'utc'))*1000) - 
CASE 
	WHEN t1.auction_id IS NOT NULL THEN t1.auction_end_date 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_date
	ELSE t1.mint_date END 
) AS sort_date,
round_to_decimals_f(CASE 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_price 
	WHEN t1.auction_id IS NOT null THEN COALESCE(t1.auction_current_bid,t1.auction_starting_bid)
	END * e.usd)
	AS filter_price_usd,
COALESCE(t1.auction_token,t1.listing_token) AS filter_token
FROM soonmarket_nft t1
LEFT JOIN soonmarket_exchange_rate_latest_v e ON e.token_symbol = 
CASE 
	WHEN t1.listing_id IS NOT NULL THEN t1.listing_token
	WHEN t1.auction_id IS NOT NULL THEN t1.auction_token
END;

COMMENT ON VIEW soonmarket_nft_v IS 'View for MyNFTs with dynamic price resolution for filtering';

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
		CASE WHEN edition_size != 0 THEN edition_size - COUNT(*) ELSE -1 END AS mintable,
		MAX(t1.mint_date) AS last_minting_date
	FROM soonmarket_nft t1
	WHERE edition_size != 1
	GROUP BY template_id,edition_size,creator) t1
LEFT JOIN LATERAL (SELECT * from soonmarket_nft_v WHERE t1.template_id=template_id AND t1.creator=creator AND edition_size!=1 LIMIT 1)t2 ON TRUE
UNION ALL
SELECT NULL,NULL,NULL,NULL, * FROM soonmarket_nft_v WHERE edition_size=1)t;

COMMENT ON VIEW soonmarket_manageable_nft_v IS 'View for manageable NFTs (parent row, creators)';

--

CREATE OR replace VIEW soonmarket_manageable_edition_nft_v as
	SELECT * 
	FROM soonmarket_nft_v WHERE edition_size!=1;

COMMENT ON VIEW soonmarket_manageable_edition_nft_v IS 'View for manageable edition NFTs (child row, creators)';	

----------------------------------
-- Collection Detail View
----------------------------------

CREATE OR replace VIEW soonmarket_collection_detail_v AS
WITH valid_sales AS (
      SELECT t1_1.sale_id AS listing_id,t1_1.collection_id,
         bool_and(COALESCE((t4.owner = t1_1.seller), false)) AS valid
        FROM ((atomicmarket_sale t1_1
          JOIN atomicmarket_sale_asset t3_1 ON ((t1_1.sale_id = t3_1.sale_id)))
          LEFT JOIN atomicassets_asset_owner_log t4 ON (((t3_1.asset_id = t4.asset_id) AND t4.current AND (NOT t4.burned))))
       WHERE (NOT (EXISTS ( SELECT 1
                FROM atomicmarket_sale_state t2_1
               WHERE (t1_1.sale_id = t2_1.sale_id))))
       GROUP BY t1_1.sale_id,t1_1.collection_id
     )
SELECT                                                                            
t1.collection_id,                                                                 
t1.creator,                                                                       
t3.royalty as collection_fee,                                                                       
t2.category,                                                                      
t2.image,          
(SELECT distinct total FROM soonmarket_collection_holder_mv WHERE collection_id=t1.collection_id) AS num_nfts,
(SELECT count(DISTINCT account) FROM soonmarket_collection_holder_mv WHERE collection_id=t1.collection_id) AS num_holders,
(SELECT COUNT(DISTINCT listing_id) FROM valid_sales v WHERE v.collection_id=t1.collection_id) AS num_listings,
(SELECT total_sales FROM soonmarket_collection_stats_mv stats WHERE stats.collection_id=t1.collection_id)  AS total_sales,
0 AS num_stars,
DATA ->> 'url' AS socials,
(SELECT total_volume_usd FROM soonmarket_collection_stats_mv stats WHERE stats.collection_id=t1.collection_id) AS total_volume_usd,
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
t2.description,
t5.schema_id,
t5.schema_name
FROM atomicassets_collection t1                                                   
LEFT JOIN atomicassets_collection_data_log t2 ON t1.collection_id = t2.collection_id and t2.current
LEFT JOIN atomicassets_collection_royalty_log t3 ON t1.collection_id = t3.collection_id and t3.current
LEFT JOIN nft_watch_blacklist b1 ON t1.collection_id = b1.collection_id           
LEFT JOIN soonmarket_internal_blacklist b2 ON t1.collection_id = b2.collection_id 
LEFT JOIN nft_watch_shielding s1 ON t1.collection_id = s1.collection_id           
LEFT JOIN soonmarket_internal_shielding s2 ON t1.collection_id = s2.collection_id
LEFT JOIN LATERAL (SELECT string_agg(schema_id,',') AS schema_id,string_agg(SCHEMA_NAME,',') AS schema_name FROM atomicassets_schema WHERE t1.collection_id=collection_id GROUP BY t1.collection_id)t5 ON TRUE;

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
	listings.asset_id,
	listings.template_id,
	t2.SERIAL,
	listing_id,
	listing_date,
	seller,
	listing_token,
	listing_price,
	listing_royalty,
	bundle_size,
	listings.index
FROM soonmarket_listing_valid_v listings
LEFT JOIN soonmarket_asset_base_v t2 ON listings.asset_id=t2.asset_id
ORDER BY t2.SERIAL asc;
COMMENT ON VIEW soonmarket_edition_listings_v IS 'Get all listings for a given edition/template';

--

CREATE OR REPLACE VIEW soonmarket_edition_bundles_v AS
SELECT
	gen_random_uuid () as id,
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
	NULL::bigint as auction_id,
	NULL::bigint as auction_start_date,
	NULL::bigint as auction_end_date,
	NULL as auction_token,
	NULL::DOUBLE precision as auction_starting_bid,
	NULL::DOUBLE precision as auction_royalty,
	NULL::DOUBLE precision as auction_current_bid,
	NULL::int as num_bids,
	NULL as highest_bidder
FROM soonmarket_edition_listings_v WHERE bundle_size IS NOT NULL AND 
	(template_id,listing_id,INDEX) IN(SELECT template_id,listing_id,min(INDEX) 
	FROM soonmarket_edition_listings_v v1 
	WHERE v1.template_id=template_id AND v1.listing_id=listing_id GROUP BY template_id,listing_id)
UNION 
SELECT  
	gen_random_uuid () as id,
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
FROM soonmarket_edition_auctions_v WHERE bundle_size IS NOT NULL AND
	(template_id,auction_id,INDEX) IN(SELECT template_id,auction_id,min(INDEX) 
	FROM soonmarket_edition_auctions_v v1 
	WHERE v1.template_id=template_id AND v1.auction_id=auction_id GROUP BY template_id,auction_id);

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
-- Profile
----------------------------------

CREATE VIEW soonmarket_asset_owner_v AS 
SELECT 
t1.owner,
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
	COALESCE(t2.num_bought,0) AS num_bought,
	t2.last_bought AS last_bought,
	COALESCE(t3.num_sold,0) AS num_sold,
	t3.last_sold AS last_sold
FROM soonmarket_profile t1
LEFT JOIN LATERAL (select COUNT(*) AS num_bought, MAX(block_timestamp) AS last_bought from soonmarket_sale_stats_v where t1.account=buyer GROUP BY buyer LIMIT 1)t2 ON TRUE
LEFT JOIN LATERAL (select COUNT(*) AS num_sold, MAX(block_timestamp) AS last_sold from soonmarket_sale_stats_v where t1.account=seller GROUP BY seller LIMIT 1)t3 ON TRUE;

----------------------------------
-- My Trading History View
----------------------------------

CREATE OR REPLACE VIEW soonmarket_my_trading_history_v AS
WITH all_sales AS(
 	SELECT
 	 'listing' AS sale_type, 
	 	t2.sale_id as sale_type_id,
		t2.buyer,
		t1.collection_id,
		t1.primary_asset_id AS asset_id,    
		t1.seller,
		t2.block_timestamp AS sale_date,
		t1.token,
		t1.price,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee AS royalty,
		t1.bundle,
		t1.bundle_size
  FROM (atomicmarket_sale_state t2
  LEFT JOIN atomicmarket_sale t1 ON ((t1.sale_id = t2.sale_id)))
  WHERE (t2.state = 3)
UNION ALL
 	SELECT 
		'auction', 
		t2.auction_id,
		t2.buyer,
		t1.collection_id,
		t1.primary_asset_id,
		t1.seller,
		t2.block_timestamp,
		t1.token,
		t2.winning_bid,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee,
		t1.bundle,
		t1.bundle_size
	FROM (atomicmarket_auction_state t2
	LEFT JOIN atomicmarket_auction t1 ON ((t1.auction_id = t2.auction_id)))
  WHERE (t2.state = 3)
UNION ALL
 	SELECT 
		'offer',
		t2.buyoffer_id,
		t1.buyer,
		t1.collection_id,
		t1.primary_asset_id,
		t1.seller,
		t2.block_timestamp,
		t1.token,
		t1.price,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee,
		t1.bundle,
		t1.bundle_size
  FROM (atomicmarket_buyoffer_state t2
  LEFT JOIN atomicmarket_buyoffer t1 ON ((t1.buyoffer_id = t2.buyoffer_id)))
  WHERE (t2.state = 3))
SELECT 
	t1.*,
	t1.price*t3.usd AS filter_price_usd,
	t2.collection_name,
	t2.collection_image,
	t2.shielded,
	t2.asset_name,
	t2.asset_media,
	t2.asset_media_type,
	t2.asset_media_preview,
	t2.serial,
	t2.edition_size,
	t2.template_id,
	'' AS owner 
FROM all_sales t1
LEFT JOIN soonmarket_asset_v t2 ON t1.asset_id = t2.asset_id
LEFT JOIN soonmarket_exchange_rate_historic_v t3 
	ON t1.token = t3.token_symbol 
	AND TO_CHAR(TO_TIMESTAMP(t1.sale_date / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00') = t3.utc_date;

COMMENT ON VIEW public.soonmarket_my_trading_history_v IS 'View for my trading history';

----------------------------------
-- My Royalties View
----------------------------------

CREATE OR REPLACE VIEW soonmarket_my_royalties_v AS
WITH all_sales AS(
 	SELECT
 	 'listing' AS sale_type, 
	 	t1.sale_id as sale_type_id,
		t1.primary_asset_id AS asset_id,    
		t2.block_timestamp AS sale_date,
		t1.token,
		t1.price,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee AS royalty,
		t1.bundle,
		t1.bundle_size,
		t1.seller,
		t2.buyer
  FROM (atomicmarket_sale_state t2
  LEFT JOIN atomicmarket_sale t1 ON ((t1.sale_id = t2.sale_id)))
  WHERE (t2.state = 3)
UNION ALL
 	SELECT 
		'auction', 
		t1.auction_id,
		t1.primary_asset_id,
		t2.block_timestamp,
		t1.token,
		t2.winning_bid,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee,
		t1.bundle,
		t1.bundle_size,
		t1.seller,
		t2.buyer
	FROM (atomicmarket_auction_state t2
	LEFT JOIN atomicmarket_auction t1 ON ((t1.auction_id = t2.auction_id)))
  WHERE (t2.state = 3)
UNION ALL
 	SELECT 
		'offer',
		t1.buyoffer_id,
		t1.primary_asset_id,
		t2.block_timestamp,
		t1.token,
		t1.price,
		t2.maker_market_fee,
		t2.taker_market_fee,
		t1.collection_fee,
		t1.bundle,
		t1.bundle_size,
		t1.seller,
		t1.buyer
  FROM (atomicmarket_buyoffer_state t2
  LEFT JOIN atomicmarket_buyoffer t1 ON ((t1.buyoffer_id = t2.buyoffer_id)))
  WHERE (t2.state = 3))
SELECT 
	t1.*,
	t2.collection_id,
	t2.collection_name,
	t2.collection_image,
	t2.creator,
	t2.shielded,
	t2.asset_name,
	t2.asset_media,
	t2.asset_media_type,
	t2.asset_media_preview,
	t2.serial,
	t2.edition_size,
	t2.template_id,
	t2.owner
FROM all_sales t1
LEFT JOIN soonmarket_asset_v t2 ON t1.asset_id = t2.asset_id;

COMMENT ON VIEW public.soonmarket_my_royalties_v IS 'View for my royalties';
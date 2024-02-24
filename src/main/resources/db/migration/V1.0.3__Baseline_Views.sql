----------------------------------
-- templates
----------------------------------

CREATE VIEW soonmarket_template_v AS
SELECT
	t1.blocknum AS blocknum, 
	GREATEST(t1.blocknum, t2.blocknum) AS blocknum_updated,
	t1.block_timestamp AS block_timestamp,
	GREATEST(t1.block_timestamp, t2.block_timestamp) AS block_timestamp_updated,
	t1.template_id,
	t1.schema_id,
	t1.collection_id,
	t1.creator,
	t1.transferable,
	t1.burnable,
	COALESCE(t2.locked_at_supply,t1.initial_max_supply) as edition_size,
	t2.locked,
	t1.name,
	t1.description,
	t1.media,
	t1.media_type,
	t1.media_preview,
	t1.immutable_data
FROM atomicassets_template t1
LEFT JOIN atomicassets_template_state t2 ON t1.template_id = t2.template_id;

----------------------------------
-- collections
----------------------------------

CREATE VIEW soonmarket_collection_v AS                                            
SELECT                                                                            
t1.blocknum AS blocknum,                                                          
GREATEST(t1.blocknum, t2.blocknum,t3.blocknum,t4.blocknum) AS blocknum_updated,   
t1.block_timestamp AS block_timestamp,                                            
GREATEST(t1.block_timestamp, t2.block_timestamp,t3.block_timestamp,t4.block_timestamp) AS block_timestamp_updated,
t1.collection_id,                                                                 
CASE WHEN b1.collection_id IS NOT NULL or b2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS blacklisted,
COALESCE(b1.block_timestamp,b2.block_timestamp) AS blacklist_date,
COALESCE(b1.reporter_comment,b2.reporter_comment) AS blacklist_reason,
CASE WHEN b1.reporter is not null THEN 'NFT Watch' WHEN b2.reporter is not null THEN 'Soon.Market' ELSE null END AS blacklist_actor,
CASE WHEN s1.collection_id IS NOT NULL or s2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS shielded,
t1.creator,                                                                                                                                               
t3.royalty as collection_fee,                                                                       
t2.category,                                                                      
t2.name,                                                                          
t2.description,                                                                   
t2.image,                                                                         
t4.allow_notify,                                                                  
t4.notify_accounts,                                                               
t4.authorized_accounts,                                                           
t2.data                                                                           
FROM atomicassets_collection t1                                                   
LEFT JOIN atomicassets_collection_data_log t2 ON t1.collection_id = t2.collection_id and t2.current
LEFT JOIN atomicassets_collection_royalty_log t3 ON t1.collection_id = t3.collection_id and t3.current
LEFT JOIN atomicassets_collection_account_log t4 ON t1.collection_id = t4.collection_id and t4.current                         
LEFT JOIN nft_watch_blacklist b1 ON t1.collection_id = b1.collection_id           
LEFT JOIN soonmarket_internal_blacklist b2 ON t1.collection_id = b2.collection_id 
LEFT JOIN nft_watch_shielding s1 ON t1.collection_id = s1.collection_id           
LEFT JOIN soonmarket_internal_shielding s2 ON t1.collection_id = s2.collection_id;

----------------------------------
-- assets
----------------------------------
CREATE OR REPLACE VIEW soonmarket_asset_base_v AS
SELECT
	t1.asset_id,
	t1.serial,
	COALESCE(t5.edition_size,1) as edition_size,
	t1.template_id,
	t1.schema_id,
	t1.collection_id,
	COALESCE(t2.name, t5.name) AS asset_name,
	COALESCE(t2.description, t5.description) AS description,
	COALESCE(t2.media, t5.media) AS asset_media,
	COALESCE(t2.media_type, t5.media_type) AS asset_media_type,
	COALESCE(t2.media_preview, t5.media_preview) AS asset_media_preview,
	t4.owner,
	CASE WHEN t1.template_id IS NOT NULL THEN t5.transferable ELSE TRUE END AS transferable,
	CASE WHEN t1.template_id IS NOT NULL THEN t5.burnable ELSE TRUE END AS burnable,
	CASE WHEN t4.burned THEN TRUE ELSE FALSE END AS burned
FROM atomicassets_asset t1
LEFT JOIN atomicassets_asset_data t2 ON t1.asset_id = t2.asset_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t1.asset_id = t4.asset_id AND t4.current
LEFT JOIN soonmarket_template_v t5 ON t1.template_id = t5.template_id;

--

CREATE OR REPLACE VIEW soonmarket_asset_v AS
SELECT
	t1.blocknum AS blocknum, 
	GREATEST(t1.blocknum, t2.blocknum,t3.blocknum,t4.blocknum) AS blocknum_updated,
	t1.block_timestamp AS block_timestamp,
	GREATEST(t1.block_timestamp, t2.block_timestamp,t3.block_timestamp,t4.block_timestamp) AS block_timestamp_updated,
	t1.asset_id,
	CASE WHEN COALESCE(t5.edition_size,1) = 1 THEN true ELSE false END one_of_one,	
	t1.serial,
	COALESCE(t5.edition_size,1) as edition_size,
	t1.template_id,
	t1.schema_id,
	t1.collection_id,
	t6.name AS collection_name,
	t6.image AS collection_image,
	t6.collection_fee as royalty,
	t6.creator,
	t6.category,
	t6.shielded,
	t6.blacklisted,
	t6.blacklist_date,
	t6.blacklist_reason,
	t6.blacklist_actor,
	t1.minter,
	t1.receiver,
	COALESCE(t4.burned,FALSE) AS burned,
	CASE WHEN t4.burned THEN t4.owner END AS burned_by,
	CASE WHEN t4.burned THEN t4.block_timestamp END AS burn_date,
	t4.owner,
	COALESCE(t4.block_timestamp,t1.block_timestamp) AS received_date,
	COALESCE(t2.name, t5.name) AS asset_name,
	COALESCE(t2.description, t5.description) AS description,
	COALESCE(t2.media, t5.media) AS asset_media,
	COALESCE(t2.media_type, t5.media_type) AS asset_media_type,
	COALESCE(t2.media_preview, t5.media_preview) AS asset_media_preview,
	COALESCE(t2.burnable, t5.burnable) AS burnable,
	COALESCE(t2.transferable, t5.transferable) AS transferable,
	t3.mutable_data,
	t3.backed_tokens,
	CASE WHEN t1.immutable_data != '{}' THEN t1.immutable_data ELSE t5.immutable_data END AS immutable_data
FROM atomicassets_asset t1
LEFT JOIN atomicassets_asset_data t2 ON t1.asset_id = t2.asset_id
LEFT JOIN atomicassets_asset_data_log t3 ON t3.asset_id = t1.asset_id and t3.current
LEFT JOIN atomicassets_asset_owner_log t4 ON t1.asset_id = t4.asset_id AND t4.current
LEFT JOIN soonmarket_template_v t5 ON t1.template_id = t5.template_id
LEFT JOIN soonmarket_collection_v t6 ON t1.collection_id = t6.collection_id;

----------------------------------
-- base views for auction
----------------------------------

CREATE VIEW soonmarket_auction_base_v as
SELECT 
	t1.auction_id,
	t5.asset_id,
	t5.template_id,
	t5.collection_id,
	t1.seller,
	t1.price AS starting_price,
	er.usd * t1.price AS starting_price_usd,	
	t4.current_bid,
	er.usd * t4.current_bid AS current_bid_usd,
	t1.token,
	t1.collection_fee,
	t1.bundle,
	t1.bundle_size,
	GREATEST (t4.updated_end_time,t1.end_time) AS auction_end,
	GREATEST (t4.updated_end_time,t1.end_time) > floor(extract(epoch from NOW() AT TIME ZONE 'UTC')*1000) as active
FROM atomicmarket_auction t1
INNER JOIN atomicmarket_auction_asset t5 ON t1.auction_id=t5.auction_id
LEFT JOIN atomicmarket_event_auction_bid_log t4 ON t4.auction_id=t1.auction_id AND t4.current
LEFT JOIN soonmarket_exchange_rate_latest_v er ON t1.token = er.token_symbol;

COMMENT ON VIEW public.soonmarket_auction_base_v IS 'Basic aggregation auf auction info to match with asset/template';	

--

CREATE OR REPLACE VIEW soonmarket_auction_v AS
SELECT 
	t1.auction_id,
	t3.asset_id,
	t5.serial,
	t3.index,	
	t3.template_id,
	t3.collection_id,
	t2.state,
	GREATEST (t4.updated_end_time,t1.end_time) > floor(extract(epoch from NOW() AT TIME ZONE 'UTC')*1000)  as active,
	t1.block_timestamp AS auction_start_date,
	GREATEST (t4.updated_end_time,t1.end_time) AS auction_end_date,
	t1.token AS auction_token,
	t1.price AS auction_starting_bid,
	t1.collection_fee as auction_royalty,
	t2.maker_market_fee as auction_maker_market_fee,
	t2.taker_market_fee as auction_taker_market_fee,
	t1.seller,
	t4.current_bid AS auction_current_bid,
	t4.block_timestamp AS auction_current_bid_date,
	t4.bid_number AS num_bids,
	t4.bidder AS highest_bidder,
	t1.bundle_size,
	t1.bundle_size is not null as bundle,
	t5.transferable,
	t5.burnable
FROM atomicmarket_auction t1
left JOIN atomicmarket_auction_state t2 ON t1.auction_id=t2.auction_id
LEFT JOIN atomicmarket_event_auction_bid_log t4 ON t4.auction_id=t1.auction_id AND t4.current
INNER JOIN atomicmarket_auction_asset t3 ON t1.auction_id = t3.auction_id
LEFT JOIN soonmarket_asset_base_v t5 ON t5.asset_id=t3.asset_id;

--

CREATE OR REPLACE VIEW soonmarket_auction_bundle_assets_v as
SELECT 
t1.auction_id,
t1.asset_id,
t1.index,
t1.template_id,
t2.collection_id,
t2.asset_name,
t2.asset_media,
t2.asset_media_type,
t2.asset_media_preview,
t2.serial,
t2.transferable,
t2.burnable,
t2.edition_size,
t2.owner
FROM soonmarket_auction_v t1 
LEFT JOIN soonmarket_asset_base_v t2 ON t1.asset_id=t2.asset_id;

----------------------------------
-- base views for sale
----------------------------------

CREATE OR replace VIEW soonmarket_listing_valid_v as
WITH valid_sales AS (
SELECT 
	t1.sale_id,
	BOOL_AND(COALESCE(t4.owner = t1.seller,FALSE)) AS VALID
FROM atomicmarket_sale t1 
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t3.asset_id=t4.asset_id AND t4.current and not t4.burned
WHERE NOT EXISTS(SELECT 1 from atomicmarket_sale_state t2 where t1.sale_id=t2.sale_id)
GROUP BY t1.sale_id
)
SELECT 
	t1.sale_id AS listing_id,
	t3.asset_id,
	t3.template_id,
	t3.collection_id,
	t2.block_timestamp AS listing_date,
	t2.price AS listing_price,
	er.usd * t2.price AS listing_price_usd,
	t2.token AS listing_token,
	t2.collection_fee AS listing_royalty,
	bundle,
	bundle_size,
	t2.seller
FROM valid_sales t1
INNER JOIN atomicmarket_sale t2 ON t1.sale_id=t2.sale_id
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN soonmarket_exchange_rate_latest_v er ON t2.token = er.token_symbol
where VALID;

--

CREATE OR REPLACE VIEW soonmarket_listing_v AS
SELECT
	t1.blocknum AS blocknum, 
	t1.block_timestamp AS listing_date,
	t1.sale_id as listing_id,
	t2.state,
	COALESCE(t5.owner = t1.seller,false) AS VALID,
	t3.asset_id,
	t4.serial,
	t3.index,
	t4.template_id,
	t1.collection_id,
	t1.bundle,
	t1.bundle_size,
	t1.seller,
	t2.buyer,
	t1.token AS listing_token,
	t1.price AS listing_price,
	t1.collection_fee as listing_royalty,
	t2.maker_market_fee as listing_maker_market_fee,
	t2.taker_market_fee as listing_taker_market_fee,
	t1.maker_marketplace,
	t2.taker_marketplace
FROM atomicmarket_sale t1
LEFT JOIN atomicmarket_sale_state t2 ON t1.sale_id=t2.sale_id
LEFT JOIN soonmarket_exchange_rate_latest_v e1 ON t1.token = e1.token_symbol
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id = t3.sale_id
LEFT JOIN atomicassets_asset t4 ON t3.asset_id=t4.asset_id
LEFT JOIN atomicassets_asset_owner_log t5 ON t5.asset_id=t4.asset_id AND t5.current;

--

CREATE OR REPLACE VIEW soonmarket_listing_bundle_assets_v as
SELECT 
	t1.listing_id,
	t1.asset_id,
	t1.index,
	t1.template_id,
	t2.asset_name,
	t2.asset_media,
	t2.asset_media_type,
	t2.asset_media_preview,
	t2.serial,
	t2.transferable,
	t2.burnable,
	t2.edition_size,
	t2.owner
FROM soonmarket_listing_v t1 
LEFT JOIN soonmarket_asset_base_v t2 ON t1.asset_id=t2.asset_id;

----------------------------------
-- base views for buyoffer
----------------------------------

CREATE OR REPLACE VIEW soonmarket_buyoffer_v AS
SELECT 
	gen_random_uuid() AS id,
	t1.blocknum AS blocknum, 
	t1.block_timestamp AS buyoffer_date,
	t1.buyoffer_id,
	t1.primary_asset_id,
	t2.asset_id,
	t2.index,
	t2.template_id,
	t4.serial,
	t4.edition_size,
	t4.asset_name,
	t4.asset_media,
	t4.asset_media_type,
	t4.asset_media_preview,
	t4.owner,
	t1.seller,
	t1.buyer,
	t1.bundle,
	t1.token,
	t1.price,
	t1.memo,
	t1.collection_fee AS royalty,
	t5.maker_market_fee,
	t5.taker_market_fee,
	t5.decline_memo
FROM atomicmarket_buyoffer t1
LEFT JOIN atomicmarket_buyoffer_asset t2 ON t1.buyoffer_id=t2.buyoffer_id
LEFT JOIN soonmarket_asset_base_v t4 ON t2.asset_id=t4.asset_id
LEFT JOIN atomicmarket_buyoffer_state t5 ON t1.buyoffer_id=t5.buyoffer_id;

COMMENT ON VIEW soonmarket_buyoffer_v IS 'Buyoffers for given asset or template';

--

CREATE OR REPLACE VIEW soonmarket_buyoffer_bundle_assets_v as
SELECT 
	t1.buyoffer_id,
	t1.asset_id,
	t1.index,
	t1.template_id,
	t1.asset_name,
	t1.asset_media,
	t1.asset_media_type,
	t1.asset_media_preview,
	t1.serial,
	t1.edition_size,
	t1.owner
FROM soonmarket_buyoffer_v t1;

COMMENT ON VIEW soonmarket_buyoffer_bundle_assets_v IS 'Get bundle assets for a buyoffer';

----------------------------------
-- last sold for views
----------------------------------

CREATE VIEW soonmarket_lsf_latest_asset_auctions_v as
WITH ranked_prices AS (
    SELECT
        a.asset_id,
        s.winning_bid AS price,
        s.block_timestamp,
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,
				r.token,
				s.buyer,
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_auction_asset a
    JOIN
        atomicmarket_auction_state s ON a.auction_id = s.auction_id
   INNER JOIN atomicmarket_auction r ON a.auction_id=r.auction_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,
    'auction' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;

COMMENT ON VIEW soonmarket_lsf_latest_asset_auctions_v IS 'Last price an asset was auctioned for';

--

CREATE VIEW soonmarket_lsf_latest_template_auctions_v as
WITH ranked_prices AS (
    SELECT
        a.template_id,
        s.winning_bid AS price,
        s.block_timestamp,	
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,
				r.token,
				s.buyer,		
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_auction_asset a
    JOIN
        atomicmarket_auction_state s ON a.auction_id = s.auction_id
   INNER JOIN atomicmarket_auction r ON a.auction_id=r.auction_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,		
    'auction' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;

COMMENT ON VIEW soonmarket_lsf_latest_template_auctions_v IS 'Last price any asset of a template was auctioned for';

--

CREATE VIEW soonmarket_lsf_latest_asset_buyoffers_v as
WITH ranked_prices AS (
    SELECT
        a.asset_id,
        r.price,
        s.block_timestamp,
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,
				r.token,
				r.buyer,						             
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_buyoffer_asset a
    JOIN
        atomicmarket_buyoffer_state s ON a.buyoffer_id = s.buyoffer_id
   INNER JOIN atomicmarket_buyoffer r ON a.buyoffer_id=r.buyoffer_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,	
   'buyoffer' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;

COMMENT ON VIEW soonmarket_lsf_latest_asset_buyoffers_v IS 'Last price an asset got a buyoffer for';

--

CREATE VIEW soonmarket_lsf_latest_template_buyoffers_v as
WITH ranked_prices AS (
    SELECT
        a.template_id,
        r.price,
        s.block_timestamp, 
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,	
				r.token,	
				r.buyer,		       
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_buyoffer_asset a
    JOIN
        atomicmarket_buyoffer_state s ON a.buyoffer_id = s.buyoffer_id
   INNER JOIN atomicmarket_buyoffer r ON a.buyoffer_id=r.buyoffer_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,
   'buyoffer' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;	

COMMENT ON VIEW soonmarket_lsf_latest_template_buyoffers_v IS 'Last price any asset of a template got a buyoffer for';		

--

CREATE VIEW soonmarket_lsf_latest_asset_sales_v as
WITH ranked_prices AS (
    SELECT
        a.asset_id,
        r.price,
        s.block_timestamp,
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,
				r.token,	
				s.buyer,				
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_sale_asset a
    JOIN
        atomicmarket_sale_state s ON a.sale_id = s.sale_id
   INNER JOIN atomicmarket_sale r ON a.sale_id=r.sale_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,	
    'sale' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;

COMMENT ON VIEW soonmarket_lsf_latest_asset_sales_v IS 'Last price an asset was sold for';

--

CREATE VIEW soonmarket_lsf_latest_template_sales_v as
WITH ranked_prices AS (
    SELECT
        a.template_id,
        r.price,
        s.block_timestamp,
				r.collection_fee as royalty,
        s.maker_market_fee,
        s.taker_market_fee,	
				r.token,
				s.buyer,				
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
    FROM
        atomicmarket_sale_asset a
    JOIN
        atomicmarket_sale_state s ON a.sale_id = s.sale_id
   INNER JOIN atomicmarket_sale r ON a.sale_id=r.sale_id
        WHERE s.state=3 AND NOT r.bundle
)
SELECT
    r1.*,	
    'sale' AS sourcetype    
FROM
    ranked_prices r1
WHERE
    rn = 1;

COMMENT ON VIEW soonmarket_lsf_latest_template_sales_v IS 'Last price any asset of a template was sold for';

--

CREATE VIEW soonmarket_last_sold_for_asset_v as
WITH all_prices AS (
	SELECT 
	  asset_id,
	  price,
	  block_timestamp,
		royalty,
		maker_market_fee,
		taker_market_fee,
		token,
		buyer,		
	  sourcetype,
	  ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY block_timestamp DESC) AS rn
	FROM
	(
		SELECT * FROM soonmarket_lsf_latest_asset_auctions_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_asset_buyoffers_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_asset_sales_v
	)aggregated
)
SELECT * FROM all_prices WHERE rn=1;

COMMENT ON VIEW soonmarket_last_sold_for_asset_v IS 'Last sold for price determined from the latest auction, buyoffer or sale';

--

CREATE VIEW soonmarket_last_sold_for_template_v as
WITH all_prices AS (
	SELECT 
	  template_id,
	  price,
	  block_timestamp,
		royalty,
		maker_market_fee,
		taker_market_fee,
		token,		
		buyer,
	  sourcetype,
	  ROW_NUMBER() OVER (PARTITION BY template_id ORDER BY block_timestamp DESC) AS rn
	FROM
	(
		SELECT * FROM soonmarket_lsf_latest_template_auctions_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_template_buyoffers_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_template_sales_v
	)aggregated
)
SELECT * FROM all_prices WHERE rn=1;

COMMENT ON VIEW soonmarket_last_sold_for_template_v IS 'Last sold for price determined from the latest auction, buyoffer or sale';



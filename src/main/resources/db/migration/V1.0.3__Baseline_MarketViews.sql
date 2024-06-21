----------------------------------
-- templates
----------------------------------

CREATE OR REPLACE VIEW soonmarket_template_v AS
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
	t4.burned
FROM atomicassets_asset t1
LEFT JOIN atomicassets_asset_data t2 ON t1.asset_id = t2.asset_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t1.asset_id = t4.asset_id AND t4.current
LEFT JOIN soonmarket_template_v t5 ON t1.template_id = t5.template_id;

----------------------------------
-- base views for transfer
----------------------------------

CREATE OR REPLACE VIEW soonmarket_transfer_v AS
SELECT 
	gen_random_uuid() AS id,
	t1.blocknum AS blocknum, 
	t1.block_timestamp AS transfer_date,
	t1.transfer_id,
	t2.asset_id,
	t4.template_id,
	t2.index,
	t4.serial,
	t4.edition_size,
	t4.asset_name,
	t4.asset_media,
	t4.asset_media_type,
	t4.asset_media_preview,
	t4.owner,
	t1.bundle,
	t1.memo,
	t1.receiver,
	t1.collection_id,
	t1.sender,
	t1.bundle_size
FROM atomicassets_transfer t1
LEFT JOIN atomicassets_transfer_asset t2 ON t1.transfer_id=t2.transfer_id
LEFT JOIN soonmarket_asset_base_v t4 ON t2.asset_id=t4.asset_id;

COMMENT ON VIEW soonmarket_transfer_v IS 'Transfers for given asset or template';

CREATE OR REPLACE VIEW soonmarket_transfer_bundle_assets_v as
SELECT 
	t1.transfer_id,
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
FROM soonmarket_transfer_v t1;

COMMENT ON VIEW soonmarket_transfer_bundle_assets_v IS 'Get bundle assets for a transfer';
----------------------------------
-- base views for auction
----------------------------------

CREATE OR REPLACE VIEW soonmarket_auction_base_v as
SELECT 
	COALESCE(t2.blocknum, t4.blocknum, t1.blocknum) AS blocknum,
  COALESCE(t2.block_timestamp, t4.block_timestamp, t1.block_timestamp) AS block_timestamp,
	t1.auction_id,
	t5.asset_id,
	t5.template_id,
	t5.collection_id,
	t1.seller,
	t1.price AS starting_price,
	er.usd * t1.price AS starting_price_usd,	
	t4.current_bid,
	t4.bid_number AS num_bids,
	er.usd * t4.current_bid AS current_bid_usd,
	t1.token,
	t1.collection_fee,
	t1.bundle,
	t1.bundle_size,
	GREATEST (t4.updated_end_time,t1.end_time) AS auction_end,
	(t2.state IS NULL OR t2.state = 5) as active,
	t5.index,
	t2.state,
	t4.bidder as highest_bidder
FROM atomicmarket_auction t1
INNER JOIN atomicmarket_auction_asset t5 ON t1.auction_id=t5.auction_id
LEFT JOIN atomicmarket_auction_bid_log t4 ON t4.auction_id=t1.auction_id AND t4.current
LEFT JOIN soonmarket_exchange_rate_latest_v er ON t1.token = er.token_symbol
left JOIN atomicmarket_auction_state t2 ON t1.auction_id=t2.auction_id;

COMMENT ON VIEW public.soonmarket_auction_base_v IS 'Basic aggregation auf auction info to match with asset/template';

--

CREATE OR REPLACE VIEW soonmarket_auction_running_v AS
WITH config AS (
	SELECT maker_fee, taker_fee, auction_reset_duration_seconds
	FROM atomicmarket_config
	ORDER BY id DESC
	LIMIT 1
)
SELECT 
	t1.auction_id,
	t2.state,
	t1.blocknum,
	t1.block_timestamp,
	t1.duration,
	t1.end_time,
	t3.blocknum AS bid_block,
	t3.block_timestamp AS bid_timestamp,
	t3.current_bid,
	t3.bidder AS buyer,
	t1.maker_marketplace,
	t3.taker_marketplace,
	t1.collection_fee AS royalty,
	config.maker_fee AS maker_market_fee,
	config.taker_fee AS taker_market_fee,
	config.auction_reset_duration_seconds
FROM config,atomicmarket_auction t1
LEFT JOIN atomicmarket_auction_bid_log t3 ON t1.auction_id = t3.auction_id AND t3.current
LEFT JOIN atomicmarket_auction_state t2 ON t1.auction_id = t2.auction_id
WHERE t2.state IS NULL or t2.state = 5;

COMMENT ON VIEW public.soonmarket_auction_running_v IS 'Basic aggregation auf auction info for auction end processing';

----------------------------------
-- base views for sale
----------------------------------

CREATE OR replace VIEW soonmarket_listing_valid_v as
SELECT 
	t1.sale_id,
	BOOL_AND(COALESCE(t4.owner = t1.seller,FALSE)) AS VALID,
	BOOL_OR(burned) AS burned
FROM atomicmarket_sale t1 
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t3.asset_id=t4.asset_id AND t4.current
WHERE NOT EXISTS(SELECT 1 from atomicmarket_sale_state t2 where t1.sale_id=t2.sale_id)
GROUP BY t1.sale_id;

CREATE OR replace VIEW soonmarket_listing_open_v as
SELECT 
	t2.blocknum,
	t2.block_timestamp,
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
	t2.seller,
	t3.index
FROM soonmarket_listing_valid_v t1
INNER JOIN atomicmarket_sale t2 ON t1.sale_id=t2.sale_id
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN soonmarket_exchange_rate_latest_v er ON t2.token = er.token_symbol
where VALID AND not burned;

----------------------------------
-- last sold for views
----------------------------------

CREATE OR REPLACE VIEW soonmarket_lsf_latest_asset_auctions_v as
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
				r.bundle,
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn,
				r.auction_id as action_id
    FROM
        atomicmarket_auction_asset a
    JOIN
        atomicmarket_auction_state s ON a.auction_id = s.auction_id
   INNER JOIN atomicmarket_auction r ON a.auction_id=r.auction_id
        WHERE s.state=3
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

CREATE OR REPLACE VIEW soonmarket_lsf_latest_template_auctions_v as
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
				r.bundle,	
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn,
				r.auction_id as action_id
    FROM
        atomicmarket_auction_asset a
    JOIN
        atomicmarket_auction_state s ON a.auction_id = s.auction_id
   INNER JOIN atomicmarket_auction r ON a.auction_id=r.auction_id
        WHERE s.state=3
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

CREATE OR REPLACE VIEW soonmarket_lsf_latest_asset_buyoffers_v as
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
				r.bundle,					             
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn,
				a.buyoffer_id as action_id
    FROM
        atomicmarket_buyoffer_asset a
    JOIN
        atomicmarket_buyoffer_state s ON a.buyoffer_id = s.buyoffer_id
   INNER JOIN atomicmarket_buyoffer r ON a.buyoffer_id=r.buyoffer_id
        WHERE s.state=3 
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

CREATE OR REPLACE VIEW soonmarket_lsf_latest_template_buyoffers_v as
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
				r.bundle,       
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn,
				a.buyoffer_id as action_id
    FROM
        atomicmarket_buyoffer_asset a
    JOIN
        atomicmarket_buyoffer_state s ON a.buyoffer_id = s.buyoffer_id
   INNER JOIN atomicmarket_buyoffer r ON a.buyoffer_id=r.buyoffer_id
        WHERE s.state=3
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

CREATE OR REPLACE VIEW soonmarket_lsf_latest_asset_sales_v as
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
				r.bundle,			
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn,
				r.sale_id as action_id
    FROM
        atomicmarket_sale_asset a
    JOIN
        atomicmarket_sale_state s ON a.sale_id = s.sale_id
   INNER JOIN atomicmarket_sale r ON a.sale_id=r.sale_id
        WHERE s.state=3
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

CREATE OR REPLACE VIEW soonmarket_lsf_latest_template_sales_v as
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
				r.bundle,			
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn,
				r.sale_id as action_id
    FROM
        atomicmarket_sale_asset a
    JOIN
        atomicmarket_sale_state s ON a.sale_id = s.sale_id
   INNER JOIN atomicmarket_sale r ON a.sale_id=r.sale_id
        WHERE s.state=3
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

CREATE OR REPLACE VIEW soonmarket_last_sold_for_asset_v as
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
		bundle,
	  ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY block_timestamp DESC) AS rn,
		action_id
	FROM
	(
		SELECT * FROM soonmarket_lsf_latest_asset_auctions_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_asset_buyoffers_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_asset_sales_v
	)aggregated
)
SELECT 
t1.*,
t1.price * COALESCE(t2.usd,t3.usd) AS price_usd
FROM all_prices t1 
LEFT JOIN soonmarket_exchange_rate_historic_v t2 
	ON t1.token=t2.token_symbol 
	AND TO_CHAR(TO_TIMESTAMP(t1.block_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00') = t2.utc_date
LEFT JOIN soonmarket_exchange_rate_latest_v t3 ON t1.token=t3.token_symbol			
WHERE rn=1;

COMMENT ON VIEW soonmarket_last_sold_for_asset_v IS 'Last sold for price determined from the latest auction, buyoffer or sale';

--

CREATE OR REPLACE VIEW soonmarket_last_sold_for_template_v as
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
		bundle,
	  ROW_NUMBER() OVER (PARTITION BY template_id ORDER BY block_timestamp DESC) AS rn,
		action_id
	FROM
	(
		SELECT * FROM soonmarket_lsf_latest_template_auctions_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_template_buyoffers_v
		UNION
		SELECT * FROM soonmarket_lsf_latest_template_sales_v
	)aggregated
)
SELECT 
t1.*,
t1.price * COALESCE(t2.usd,t3.usd) AS price_usd
FROM all_prices t1
LEFT JOIN soonmarket_exchange_rate_historic_v t2 
	ON t1.token=t2.token_symbol 
	AND TO_CHAR(TO_TIMESTAMP(t1.block_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00') = t2.utc_date
LEFT JOIN soonmarket_exchange_rate_latest_v t3 ON t1.token=t3.token_symbol		
WHERE rn=1;

COMMENT ON VIEW soonmarket_last_sold_for_template_v IS 'Last sold for price determined from the latest auction, buyoffer or sale';



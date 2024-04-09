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
	t4.bid_number AS num_bids,
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

CREATE OR REPLACE VIEW soonmarket_auction_running_v AS
WITH config AS (
	SELECT maker_fee, taker_fee
	FROM atomicmarket_config
	ORDER BY id DESC
	LIMIT 1
)
SELECT 
	t1.auction_id,
	t1.blocknum,
	t1.block_timestamp,
	t1.duration,
	t3.blocknum AS bid_block,
	t3.block_timestamp AS bid_timestamp,
	t3.current_bid,
	t3.bidder AS buyer,
	t1.maker_marketplace,
	t3.taker_marketplace,
	t1.collection_fee,
	config.maker_fee AS maker_market_fee,
	config.taker_fee AS taker_market_fee
FROM config,atomicmarket_auction t1
LEFT JOIN atomicmarket_event_auction_bid_log t3 ON t1.auction_id = t3.auction_id AND t3.current
WHERE NOT EXISTS (SELECT auction_id FROM atomicmarket_auction_state t2 WHERE t1.auction_id=t2.auction_id);

COMMENT ON VIEW public.soonmarket_auction_running_v IS 'Basic aggregation auf auction info for auction end processing';

----------------------------------
-- base views for sale
----------------------------------

CREATE OR replace VIEW soonmarket_listing_valid_v as
WITH valid_sales AS (
SELECT 
	t1.sale_id,
	BOOL_AND(COALESCE(t4.owner = t1.seller,FALSE)) AS VALID,
	BOOL_OR(burned) AS burned
FROM atomicmarket_sale t1 
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN atomicassets_asset_owner_log t4 ON t3.asset_id=t4.asset_id AND t4.current
WHERE NOT EXISTS(SELECT 1 from atomicmarket_sale_state t2 where t1.sale_id=t2.sale_id)
GROUP BY t1.sale_id
)
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
FROM valid_sales t1
INNER JOIN atomicmarket_sale t2 ON t1.sale_id=t2.sale_id
INNER JOIN atomicmarket_sale_asset t3 ON t1.sale_id=t3.sale_id
LEFT JOIN soonmarket_exchange_rate_latest_v er ON t2.token = er.token_symbol
where VALID AND not burned;

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
				r.bundle,
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
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
				r.bundle,	
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
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
				r.bundle,					             
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
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
				r.bundle,       
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
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
				r.bundle,			
        ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY s.block_timestamp DESC) AS rn
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
				r.bundle,			
        ROW_NUMBER() OVER (PARTITION BY a.template_id ORDER BY s.block_timestamp DESC) AS rn
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
		bundle,
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



----------------------------------
-- Market actions (buys) stats
----------------------------------

CREATE OR replace VIEW soonmarket_sale_stats_v as
Select
	t2.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t1.price 
	FROM atomicmarket_sale_state t2
	LEFT JOIN atomicmarket_sale t1  ON t1.sale_id=t2.sale_id
	WHERE STATE=3 
UNION ALL
SELECT 
	t2.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t1.price 
	FROM atomicmarket_auction_state t2 
	LEFT JOIN atomicmarket_auction t1  ON t1.auction_id=t2.auction_id
	WHERE STATE=3 
UNION ALL
SELECT  
	t1.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t1.price 
	FROM atomicmarket_buyoffer_state t2
	LEFT JOIN atomicmarket_buyoffer t1 ON t1.buyoffer_id=t2.buyoffer_id
	WHERE STATE=3;	

----------------------------------
-- Collection Holder
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_collection_holder_mv AS
WITH collection_total AS(
	SELECT 
	COUNT(*) AS total,
	sum(CASE WHEN burned THEN 1 ELSE 0 end) AS burned, 
	collection_id
FROM atomicassets_asset_owner_log  t2
	LEFT JOIN atomicassets_asset t1 ON t1.asset_id=t2.asset_id AND current
	GROUP BY collection_Id
),
collection_owner AS (
	SELECT 
	t2.owner AS account,
	t1.collection_id
	FROM atomicassets_asset_owner_log  t2
	LEFT JOIN atomicassets_asset t1 ON t1.asset_id=t2.asset_id AND current AND NOT burned
)				
SELECT 
	ROW_NUMBER() OVER (PARTITION BY collection_id ORDER BY t1.num_nfts DESC) AS rank,
	account,
	t1.collection_id,
	total-burned AS total,
	burned,
	COUNT(*) AS num_nfts,
	round_to_decimals_f((COUNT(*)::DOUBLE PRECISION / (total-burned)) * 100) AS owned,
	t3.num_bought
FROM collection_owner t1
LEFT JOIN collection_total t2 ON t1.collection_id=t2.collection_id
LEFT JOIN (select COUNT(buyer) AS num_bought, buyer, collection_id from soonmarket_sale_stats_v GROUP BY collection_id,buyer)t3 ON t1.collection_id=t3.collection_id AND buyer=t1.account
GROUP BY t1.collection_id, account,total,burned,num_bought;

COMMENT ON MATERIALIZED VIEW soonmarket_collection_holder_mv IS 'List of collection holders and stats';

CREATE UNIQUE INDEX pk_soonmarket_collection_holder_mv ON soonmarket_collection_holder_mv (account,collection_id);

----------------------------------
-- Global Stats
----------------------------------
CREATE OR REPLACE VIEW soonmarket_global_stats_24h_v as
	SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	(SELECT usd FROM soonmarket_exchange_rate_latest_v WHERE token_symbol='XPR') AS xpr_usd
	FROM
	(
		SELECT DISTINCT 
			price, t2.block_timestamp AS utc_date, token FROM atomicmarket_sale_state t2
			LEFT JOIN atomicmarket_sale t1  ON t1.sale_id=t2.sale_id
			WHERE STATE=3 
		UNION ALL
		SELECT DISTINCT
			winning_bid, t2.end_time, token 
			FROM atomicmarket_auction_state t2 
			LEFT JOIN atomicmarket_auction t1  ON t1.auction_id=t2.auction_id
			WHERE STATE=3 
		UNION ALL
		SELECT DISTINCT 
			price,t2.block_timestamp, token 
			FROM atomicmarket_buyoffer_state t2
			LEFT JOIN atomicmarket_buyoffer t1 ON t1.buyoffer_id=t2.buyoffer_id
			WHERE STATE=3 	
	)vol	
	LEFT JOIN 
	soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE vol.utc_date BETWEEN 
floor(extract(epoch FROM (CURRENT_DATE - '1 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000)
AND
floor(extract(epoch FROM CURRENT_DATE AT TIME ZONE 'UTC')*1000);

----------------------------------
-- Global Collection Stats
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_collection_stats_mv as
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	vol.collection_id,
	(Select count(distinct asset_id) from atomicassets_asset where collection_id=vol.collection_id) as num_nfts
FROM soonmarket_sale_stats_v vol
LEFT JOIN soonmarket_exchange_rate_historic_v her ON
her.utc_date=TO_CHAR(TO_TIMESTAMP(vol.block_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00')
AND her.token_symbol=vol.token
GROUP BY vol.collection_id;

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_mv ON soonmarket_collection_stats_mv (collection_id);

----------------------------------
-- Timeframed Collection Stats
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_collection_stats_7d_mv as
WITH stats AS(
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	vol.collection_id
	FROM soonmarket_sale_stats_v vol
LEFT JOIN soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE 
	vol.block_timestamp 
		BETWEEN floor(extract(epoch FROM (CURRENT_DATE - '7 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000)
	AND
		floor(extract(epoch FROM CURRENT_DATE AT TIME ZONE 'UTC')*1000)
GROUP BY vol.collection_id
)
SELECT 
t1.* ,
c2.name AS collection_name,
c2.image as collection_image,
c1.creator,
a1.shielded,
round_to_decimals_f(t3.listing_price_usd) AS floor_price_usd,
t4.total as unique_holders,
(SELECT COUNT(DISTINCT listing_id) FROM soonmarket_listing_valid_v v WHERE v.collection_id=t1.collection_id) AS num_listed,
(SELECT COUNT(*) FROM atomicassets_asset_owner_log WHERE current and not burned and asset_id in (select asset_id from atomicassets_asset WHERE collection_id=t1.collection_id)) AS num_assets
FROM stats t1
LEFT JOIN atomicassets_collection c1 ON t1.collection_id=c1.collection_id 
LEFT JOIN atomicassets_collection_data_log c2 ON t1.collection_id=c2.collection_id AND c2.current
LEFT JOIN soonmarket_collection_audit_info_v a1 ON t1.collection_id=a1.collection_id
LEFT JOIN LATERAL (SELECT listing_price_usd,listing_token, listing_price,listing_royalty from soonmarket_listing_valid_v where t1.collection_id = collection_id AND NOT bundle ORDER BY listing_price_usd ASC LIMIT 1)t3 ON TRUE
LEFT JOIN LATERAL (select total from soonmarket_collection_holder_mv WHERE t1.collection_id=collection_id LIMIT 1)t4 ON TRUE;

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_7d_mv ON soonmarket_collection_stats_7d_mv (collection_id);

--

CREATE MATERIALIZED VIEW soonmarket_collection_stats_30d_mv as
WITH stats AS(
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	vol.collection_id
	FROM soonmarket_sale_stats_v vol
LEFT JOIN soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE 
	vol.block_timestamp 
		BETWEEN floor(extract(epoch FROM (CURRENT_DATE - '30 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000)
	AND
		floor(extract(epoch FROM CURRENT_DATE AT TIME ZONE 'UTC')*1000)
GROUP BY vol.collection_id
)
SELECT 
t1.* ,
c2.name AS collection_name,
c2.image as collection_image,
c1.creator,
a1.shielded,
round_to_decimals_f(t3.listing_price_usd) AS floor_price_usd,
t4.total as unique_holders,
(SELECT COUNT(DISTINCT listing_id) FROM soonmarket_listing_valid_v v WHERE v.collection_id=t1.collection_id) AS num_listed,
(SELECT COUNT(*) FROM atomicassets_asset_owner_log WHERE current and not burned and asset_id in (select asset_id from atomicassets_asset WHERE collection_id=t1.collection_id)) AS num_assets
FROM stats t1
LEFT JOIN atomicassets_collection c1 ON t1.collection_id=c1.collection_id 
LEFT JOIN atomicassets_collection_data_log c2 ON t1.collection_id=c2.collection_id AND c2.current
LEFT JOIN soonmarket_collection_audit_info_v a1 ON t1.collection_id=a1.collection_id
LEFT JOIN LATERAL (SELECT listing_price_usd,listing_token, listing_price,listing_royalty from soonmarket_listing_valid_v where t1.collection_id = collection_id AND NOT bundle ORDER BY listing_price_usd ASC LIMIT 1)t3 ON TRUE
LEFT JOIN LATERAL (select total from soonmarket_collection_holder_mv WHERE t1.collection_id=collection_id LIMIT 1)t4 ON TRUE;

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_30d_mv ON soonmarket_collection_stats_30d_mv (collection_id);

--

CREATE MATERIALIZED VIEW soonmarket_collection_stats_180d_mv as
WITH stats AS(
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	vol.collection_id
	FROM soonmarket_sale_stats_v vol
LEFT JOIN soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE 
	vol.block_timestamp 
		BETWEEN floor(extract(epoch FROM (CURRENT_DATE - '180 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000)
	AND
		floor(extract(epoch FROM CURRENT_DATE AT TIME ZONE 'UTC')*1000)
GROUP BY vol.collection_id
)
SELECT 
t1.* ,
c2.name AS collection_name,
c2.image as collection_image,
c1.creator,
a1.shielded,
round_to_decimals_f(t3.listing_price_usd) AS floor_price_usd,
t4.total as unique_holders,
(SELECT COUNT(DISTINCT listing_id) FROM soonmarket_listing_valid_v v WHERE v.collection_id=t1.collection_id) AS num_listed,
(SELECT COUNT(*) FROM atomicassets_asset_owner_log WHERE current and not burned and asset_id in (select asset_id from atomicassets_asset WHERE collection_id=t1.collection_id)) AS num_assets
FROM stats t1
LEFT JOIN atomicassets_collection c1 ON t1.collection_id=c1.collection_id 
LEFT JOIN atomicassets_collection_data_log c2 ON t1.collection_id=c2.collection_id AND c2.current
LEFT JOIN soonmarket_collection_audit_info_v a1 ON t1.collection_id=a1.collection_id
LEFT JOIN LATERAL (SELECT listing_price_usd,listing_token, listing_price,listing_royalty from soonmarket_listing_valid_v where t1.collection_id = collection_id AND NOT bundle ORDER BY listing_price_usd ASC LIMIT 1)t3 ON TRUE
LEFT JOIN LATERAL (select total from soonmarket_collection_holder_mv WHERE t1.collection_id=collection_id LIMIT 1)t4 ON TRUE;

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_180d_mv ON soonmarket_collection_stats_180d_mv (collection_id);
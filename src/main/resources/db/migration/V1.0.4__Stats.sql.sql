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
	collection_id,
	sum(CASE WHEN _type = 'l' THEN 1 ELSE 0 END) AS sales,
	sum(CASE WHEN _type = 'bl' THEN 1 ELSE 0 END) AS bundle_sales,
	sum(CASE WHEN _type = 'a' THEN 1 ELSE 0 END) AS auctions,
	sum(CASE WHEN _type = 'ba' THEN 1 ELSE 0 END) AS bundle_auctions,
	sum(CASE WHEN _type = 'b' THEN 1 ELSE 0 END) AS buyoffers,
	sum(CASE WHEN _type = 'bb' THEN 1 ELSE 0 END) AS bundle_buyoffers
FROM
(
	SELECT DISTINCT sl.listing_id, sl.listing_price AS price,sl.listing_date AS utc_date, listing_token AS token,collection_id, 'l' AS _type FROM soonmarket_listing_v sl WHERE STATE=3 AND NOT bundle 
	UNION ALL
	SELECT DISTINCT sl.listing_id, sl.listing_price AS price,sl.listing_date AS utc_date, listing_token AS token,collection_id, 'bl' AS _type FROM soonmarket_listing_v sl WHERE STATE=3 AND bundle
	UNION ALL
	SELECT DISTINCT auction_id, sl.auction_current_bid,sl.auction_end_date, auction_token,collection_id, 'a' FROM soonmarket_auction_v sl WHERE STATE=3 AND NOT bundle
	UNION ALL
	SELECT DISTINCT auction_id, sl.auction_current_bid,sl.auction_end_date, auction_token,collection_id, 'ba' FROM soonmarket_auction_v sl WHERE STATE=3 AND bundle
	UNION ALL
	SELECT DISTINCT buyoffer_id, price,buyoffer_update_date, token,collection_id,'b' FROM soonmarket_buyoffer_v  WHERE STATE=3 AND NOT bundle
	UNION ALL
	SELECT DISTINCT buyoffer_id, price,buyoffer_update_date, token,collection_id,'bb' FROM soonmarket_buyoffer_v  WHERE STATE=3 AND bundle
)vol	
LEFT JOIN soonmarket_exchange_rate_historic_v her ON
her.utc_date=get_utc_date_f(vol.utc_date) 
AND her.token_symbol=vol.token
GROUP BY collection_id;

----------------------------------
-- Timeframed Collection Stats
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_collection_stats_7d_mv as
WITH stats AS(
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	vol.collection_id
	FROM
	(
		SELECT DISTINCT 
			price, t2.block_timestamp AS utc_date, token, collection_id
			FROM atomicmarket_sale_state t2
			LEFT JOIN atomicmarket_sale t1  ON t1.sale_id=t2.sale_id
			WHERE STATE=3 
		UNION ALL
		SELECT DISTINCT
			winning_bid, t2.end_time, token , collection_id
			FROM atomicmarket_auction_state t2 
			LEFT JOIN atomicmarket_auction t1  ON t1.auction_id=t2.auction_id
			WHERE STATE=3 
		UNION ALL
		SELECT DISTINCT 
			price,t2.block_timestamp, token, collection_id
			FROM atomicmarket_buyoffer_state t2
			LEFT JOIN atomicmarket_buyoffer t1 ON t1.buyoffer_id=t2.buyoffer_id
			WHERE STATE=3 	
	)vol	
LEFT JOIN soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE 
	vol.utc_date 
		BETWEEN floor(extract(epoch FROM (CURRENT_DATE - '7 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000)
	AND
		floor(extract(epoch FROM CURRENT_DATE AT TIME ZONE 'UTC')*1000)
GROUP BY vol.collection_id
)
SELECT 
t1.* ,
t2.name AS collection_name,
t2.image as collection_image,
t2.creator,
t2.shielded,
round_to_decimals_f(t3.listing_price_usd) AS floor_price_usd,
t4.total as unique_holders,
(SELECT COUNT(DISTINCT listing_id) FROM soonmarket_listing_valid_v v WHERE v.collection_id=t1.collection_id) AS num_listed,
(SELECT COUNT(*) FROM soonmarket_asset_base_v WHERE collection_id=t1.collection_id AND NOT burned) AS num_assets
FROM stats t1
LEFT JOIN soonmarket_collection_v t2 ON t1.collection_id=t2.collection_id
LEFT JOIN LATERAL (SELECT listing_price_usd,listing_token, listing_price,listing_royalty from soonmarket_listing_valid_v where t1.collection_id = collection_id ORDER BY listing_price_usd ASC LIMIT 1)t3 ON TRUE
LEFT JOIN LATERAL (select total from soonmarket_collection_holder_v WHERE t1.collection_id=collection_id LIMIT 1)t4 ON true
WHERE NOT blacklisted;
----------------------------------
-- Market actions (buys) stats
----------------------------------

CREATE OR replace VIEW soonmarket_sale_stats_v as
Select
	t2.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t1.price,t1.bundle_size,'listing' as sale_type, t1.primary_asset_id as asset_id, t1.sale_id
	FROM atomicmarket_sale_state t2
	LEFT JOIN atomicmarket_sale t1  ON t1.sale_id=t2.sale_id
	WHERE STATE=3 
UNION ALL
SELECT 
	t2.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t2.winning_bid,t1.bundle_size,'auction', t1.primary_asset_id, t1.auction_id
	FROM atomicmarket_auction_state t2 
	LEFT JOIN atomicmarket_auction t1  ON t1.auction_id=t2.auction_id
	WHERE STATE=3 
UNION ALL
SELECT  
	t1.buyer,t1.collection_id,seller,t2.block_timestamp,t1.token,t1.price,t1.bundle_size,'buyoffer', t1.primary_asset_id, t1.buyoffer_id
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
	ROW_NUMBER() OVER (PARTITION BY t1.collection_id ORDER BY COUNT(*) DESC) AS rank,
	account,
	t1.collection_id,
	total-burned AS total,
	total AS minted,
	burned AS burned,
	COUNT(*) AS num_nfts,
	round_to_decimals_f((COUNT(*)::DOUBLE PRECISION / (total-burned)) * 100) AS owned,
	coalesce(t3.num_bought,0) AS num_bought,
	coalesce(t4.num_sold,0) AS num_sold,
	COALESCE(t5.num_sent,0) AS num_sent,
	COALESCE(t6.num_received,0) AS num_received
FROM collection_owner t1
LEFT JOIN collection_total t2 ON t1.collection_id=t2.collection_id
LEFT JOIN (select SUM(COALESCE(bundle_size,1)) AS num_bought, buyer, collection_id from soonmarket_sale_stats_v GROUP BY collection_id,buyer)t3 ON t1.collection_id=t3.collection_id AND buyer=t1.account
LEFT JOIN (select SUM(COALESCE(bundle_size,1)) AS num_sold, seller, collection_id from soonmarket_sale_stats_v GROUP BY collection_id,seller)t4 ON t1.collection_id=t4.collection_id AND seller=t1.account
LEFT JOIN (select SUM(COALESCE(bundle_size,1)) AS num_sent, sender, collection_id from soonmarket_transfer_v WHERE receiver NOT IN ('atomicmarket','token.escrow') GROUP BY collection_id,sender)t5 ON t1.collection_id=t5.collection_id AND sender=t1.account
LEFT JOIN (select SUM(COALESCE(bundle_size,1)) AS num_received, receiver, collection_id from soonmarket_transfer_v WHERE sender NOT IN ('atomicmarket','token.escrow') GROUP BY collection_id,receiver)t6 ON t1.collection_id=t6.collection_id AND receiver=t1.account
GROUP BY t1.collection_id, account,total,burned,num_bought,num_sold,num_sent,num_received;

COMMENT ON MATERIALIZED VIEW soonmarket_collection_holder_mv IS 'List of collection holders and stats';

CREATE UNIQUE INDEX pk_soonmarket_collection_holder_mv ON soonmarket_collection_holder_mv (account,collection_id);

----------------------------------
-- Top NFT Sales
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_top_nft_sales_mv AS
SELECT 
	vol.*,
    round_to_decimals_f(her.usd * vol.price) AS price_usd,    
	v1.asset_name,
	v1.asset_media,
	v1.asset_media_type,
	v1.asset_media_preview,
	v1.collection_name,
	v1.collection_image,
	v1.shielded,
	v1.blacklisted,
	v1.serial,
	v1.edition_size
FROM soonmarket_sale_stats_v vol
LEFT JOIN soonmarket_exchange_rate_historic_v her 
    ON her.utc_date::text = to_char(
        (to_timestamp((vol.block_timestamp / 1000)::double precision) AT TIME ZONE 'UTC'::text), 
        'YYYY-MM-DD 00:00:00'::text
    ) 
    AND her.token_symbol::text = vol.token
LEFT JOIN soonmarket_asset_v v1 ON vol.asset_id=v1.asset_id
ORDER BY 
    price_usd DESC NULLS LAST;

CREATE UNIQUE INDEX pk_soonmarket_top_nft_sales_mv ON soonmarket_top_nft_sales_mv (asset_id,sale_id,sale_type);

----------------------------------
-- Global Stats
----------------------------------
CREATE OR REPLACE VIEW soonmarket_global_stats_24h_v as
	SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(*) AS total_sales,
	(SELECT usd FROM soonmarket_exchange_rate_latest_v WHERE token_symbol='XPR') AS xpr_usd	
	FROM soonmarket_sale_stats_v vol	
	LEFT JOIN 
	soonmarket_exchange_rate_latest_v her ON her.token_symbol=vol.token
WHERE vol.block_timestamp >= floor(extract(epoch FROM (NOW() - '1 day'::INTERVAL ) AT TIME ZONE 'UTC')*1000);

----------------------------------
-- Global Collection Stats
----------------------------------

CREATE MATERIALIZED VIEW soonmarket_collection_stats_mv as
SELECT
	round_to_decimals_f(sum(her.usd*price)) AS total_volume_usd,
	COUNT(vol.*) AS total_sales,
	t1.collection_id,
	(Select count(distinct asset_id) from atomicassets_asset where collection_id=t1.collection_id) as num_nfts
FROM atomicassets_collection t1
left join soonmarket_sale_stats_v vol on t1.collection_id = vol.collection_id
LEFT JOIN soonmarket_exchange_rate_historic_v her ON
her.utc_date=TO_CHAR(TO_TIMESTAMP(vol.block_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00')
AND her.token_symbol=vol.token
GROUP BY t1.collection_id;

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_mv ON soonmarket_collection_stats_mv (collection_id);

----------------------------------
-- Timeframed Collection Stats
----------------------------------

CREATE OR REPLACE FUNCTION create_collection_stats_mv(time_interval INTERVAL, mv_name TEXT)
RETURNS VOID AS $$
DECLARE 
	_condition varchar;
BEGIN

		IF time_interval IS NULL 
			THEN _condition = '';
		ELSE
			_condition=format('WHERE vol.block_timestamp >= floor(extract(epoch FROM (CURRENT_DATE - ''%s''::INTERVAL) AT TIME ZONE ''UTC'') * 1000)', time_interval);
		END IF;

    EXECUTE format('
    CREATE MATERIALIZED VIEW %I AS
    WITH stats AS (
        SELECT
            round_to_decimals_f(sum(her.usd * vol.price)) AS total_volume_usd,
            COUNT(*) AS total_sales,
            vol.collection_id
        FROM soonmarket_sale_stats_v vol
        LEFT JOIN soonmarket_exchange_rate_historic_v her 
            ON her.utc_date = TO_CHAR(TO_TIMESTAMP(vol.block_timestamp / 1000) AT TIME ZONE ''UTC'', ''YYYY-MM-DD 00:00:00'')
            AND her.token_symbol = vol.token
        %s
        GROUP BY vol.collection_id
    ),
    listing AS (
        SELECT 
            collection_id, 
            MIN(listing_price_usd) AS floor_price_usd
        FROM soonmarket_listing_open_v 
        WHERE NOT bundle 
        GROUP BY collection_id
    ),
    unique_holders AS (
        SELECT 
            collection_id, 
            total AS unique_holders 
        FROM soonmarket_collection_holder_mv
    ),
    num_listed_assets AS (
        SELECT 
            collection_id, 
            COUNT(DISTINCT listing_id) AS num_listed
        FROM soonmarket_listing_open_v 
        GROUP BY collection_id
    ),
    num_assets AS (
        SELECT 
            collection_id, 
            COUNT(*) AS num_assets
        FROM atomicassets_asset_owner_log ao
        JOIN atomicassets_asset a 
            ON ao.asset_id = a.asset_id 
        WHERE ao.current 
            AND NOT ao.burned 
        GROUP BY a.collection_id
    )
    SELECT DISTINCT ON (t1.collection_id)
        t1.collection_id,
        t1.total_volume_usd,
        t1.total_sales,
        c2.name AS collection_name, 
        c2.image AS collection_image, 
        c1.creator, 
        a1.shielded, 
        a1.blacklisted, 
        a1.blacklist_date, 
        a1.blacklist_reason, 
        a1.blacklist_actor, 
        round_to_decimals_f(t3.floor_price_usd) AS floor_price_usd, 
        t4.unique_holders, 
        t5.num_listed, 
        t6.num_assets
    FROM stats t1
    LEFT JOIN atomicassets_collection c1 
        ON t1.collection_id = c1.collection_id 
    LEFT JOIN atomicassets_collection_data_log c2 
        ON t1.collection_id = c2.collection_id 
        AND c2.current
    LEFT JOIN soonmarket_collection_audit_info_v a1 
        ON t1.collection_id = a1.collection_id
    LEFT JOIN listing t3 
        ON t1.collection_id = t3.collection_id
    LEFT JOIN unique_holders t4 
        ON t1.collection_id = t4.collection_id
    LEFT JOIN num_listed_assets t5 
        ON t1.collection_id = t5.collection_id
    LEFT JOIN num_assets t6 
        ON t1.collection_id = t6.collection_id;', mv_name, _condition);
    
END;
$$ LANGUAGE plpgsql;

SELECT create_collection_stats_mv(INTERVAL '7 days', 'soonmarket_collection_stats_7d_mv');
SELECT create_collection_stats_mv(INTERVAL '30 days', 'soonmarket_collection_stats_30d_mv');
SELECT create_collection_stats_mv(INTERVAL '180 days', 'soonmarket_collection_stats_180d_mv');
SELECT create_collection_stats_mv(null, 'soonmarket_collection_stats_all_mv');

CREATE UNIQUE INDEX pk_soonmarket_collection_stats_7d_mv ON soonmarket_collection_stats_7d_mv (collection_id);
CREATE UNIQUE INDEX pk_soonmarket_collection_stats_30d_mv ON soonmarket_collection_stats_30d_mv (collection_id);
CREATE UNIQUE INDEX pk_soonmarket_collection_stats_180d_mv ON soonmarket_collection_stats_180d_mv (collection_id);
CREATE UNIQUE INDEX pk_soonmarket_collection_stats_all_mv ON soonmarket_collection_stats_all_mv (collection_id);
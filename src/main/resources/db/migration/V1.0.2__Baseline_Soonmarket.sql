----------------------------------
-- Utilities
----------------------------------

CREATE OR REPLACE FUNCTION public.round_to_decimals_f(
	_value anyelement,
	_decimals integer DEFAULT 2)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
			BEGIN
			RETURN _value::numeric(30,2);
			END;			
$BODY$;

--

CREATE OR REPLACE FUNCTION public.get_utc_date_f(_timestamp bigint)
RETURNS text
LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
	date_result text;
	
BEGIN 
	SELECT TO_CHAR(TO_TIMESTAMP(_timestamp / 1000) AT TIME ZONE 'UTC', 'YYYY-MM-DD 00:00:00')
	INTO date_result;
	
	RETURN date_result;
END;	
$BODY$;

----------------------------------
-- account 
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_profile
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    has_kyc boolean DEFAULT false,
    has_image boolean DEFAULT false,
    account TEXT NOT NULL,
		bio TEXT,
		has_banner boolean,
		num_followers int,
    PRIMARY KEY (account)
)
TABLESPACE pg_default;

----------------------------------
-- blacklisting / shielding tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_internal_shielding
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE TABLE IF NOT EXISTS public.soonmarket_internal_blacklist
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE TABLE IF NOT EXISTS public.nft_watch_blacklist
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
    reviewer TEXT NULL,
    reviewer_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE TABLE IF NOT EXISTS public.nft_watch_shielding
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
		reviewer TEXT NULL,
    reviewer_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE VIEW soonmarket_collection_audit_info_v AS                                            
SELECT                                                                            
t1.collection_id,                                                                 
CASE WHEN b1.collection_id IS NOT NULL or b2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS blacklisted,
COALESCE(b1.block_timestamp,b2.block_timestamp) AS blacklist_date,
COALESCE(b1.reporter_comment,b2.reporter_comment) AS blacklist_reason,
CASE WHEN b1.reporter is not null THEN 'NFT Watch' WHEN b2.reporter is not null THEN 'Soon.Market' ELSE null END AS blacklist_actor,
CASE WHEN s1.collection_id IS NOT NULL or s2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS shielded
FROM atomicassets_collection t1                                                   
LEFT JOIN nft_watch_blacklist b1 ON t1.collection_id = b1.collection_id           
LEFT JOIN soonmarket_internal_blacklist b2 ON t1.collection_id = b2.collection_id 
LEFT JOIN nft_watch_shielding s1 ON t1.collection_id = s1.collection_id           
LEFT JOIN soonmarket_internal_shielding s2 ON t1.collection_id = s2.collection_id;

----------------------------------
-- internal services tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_exchange_rate
(
    id BIGSERIAL NOT NULL,
    date_created timestamp(6) without time zone,
    date_changed timestamp(6) without time zone,
    asset_id bigint NOT NULL,
    _timestamp bigint,
    utc_date character varying(64) ,
    usd double precision,
    eur double precision,
    source character varying(1024) ,
    description character varying(4096) ,
    PRIMARY KEY (id)
)
TABLESPACE pg_default;

CREATE UNIQUE INDEX IF NOT EXISTS idx_soonmarket_exchange_rate_id_timestamp
    ON public.soonmarket_exchange_rate USING btree
    (asset_id ASC NULLS LAST, _timestamp ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE TABLE IF NOT EXISTS public.soonmarket_exchange_rate_asset
(
    id BIGSERIAL NOT NULL,
    date_created timestamp(6) without time zone,
    date_changed timestamp(6) without time zone,
    symbol character varying(32) ,
    name character varying(32) ,
    external_id character varying(1024) ,
    sync_url_historic character varying(1024) ,
    token_symbol character varying(32) ,
    source character varying(1024) ,
    token_precision integer,
    ignore boolean DEFAULT false,
    PRIMARY KEY (id)
)
TABLESPACE pg_default;

CREATE UNIQUE INDEX IF NOT EXISTS idx_soonmarket_exchange_rate_asset_token_symbol
    ON public.soonmarket_exchange_rate_asset USING btree
    (token_symbol)
    TABLESPACE pg_default;

CREATE OR REPLACE VIEW public.soonmarket_exchange_rate_historic_v
 AS
 SELECT er.id,
    er.asset_id,
    era.symbol,
    era.name,
    er._timestamp,
    er.utc_date,
    er.usd,
    er.eur,
    era.token_symbol
   FROM soonmarket_exchange_rate_asset era
     JOIN soonmarket_exchange_rate er ON era.id = er.asset_id;


CREATE OR REPLACE VIEW public.soonmarket_exchange_rate_latest_v
 AS
 SELECT t.id,
    t.asset_id,
    era.symbol,
    era.name,
    t._timestamp,
    t.utc_date,
    t.usd,
    t.eur,
    era.token_symbol,
    era.token_precision
   FROM soonmarket_exchange_rate_asset era
     JOIN ( SELECT soonmarket_exchange_rate.id,
            soonmarket_exchange_rate.asset_id,
            soonmarket_exchange_rate._timestamp,
            soonmarket_exchange_rate.utc_date,
            soonmarket_exchange_rate.usd,
            soonmarket_exchange_rate.eur
           FROM soonmarket_exchange_rate
          WHERE ((soonmarket_exchange_rate.asset_id, soonmarket_exchange_rate._timestamp) IN ( SELECT exchange_rate_daily_1.asset_id,
                    max(exchange_rate_daily_1._timestamp) AS max
                   FROM soonmarket_exchange_rate exchange_rate_daily_1
                  GROUP BY exchange_rate_daily_1.asset_id))) t ON era.id = t.asset_id;

--


CREATE OR REPLACE VIEW public.soonmarket_exchange_rate_gaps_v
 AS
 WITH timespan AS (
         WITH mindates AS (
                 SELECT min(utc_date::text) AS _min,
                    asset_id
                   FROM soonmarket_exchange_rate t1
                  GROUP BY asset_id
                  ORDER BY asset_id
                )
         SELECT md.asset_id,
            s._date
           FROM mindates md,
            LATERAL generate_series(md._min::timestamp without time zone, (now()::date - 1)::timestamp without time zone, '24:00:00'::interval) s(_date)
        )
 SELECT asset_id,
    _date AS utc_date,
    EXTRACT(epoch FROM _date) * 1000::numeric AS _timestamp
   FROM timespan
  WHERE NOT ((_date, asset_id) IN ( SELECT sm.utc_date::timestamp without time zone AS utc_date,
            ts.asset_id
           FROM soonmarket_exchange_rate sm
             JOIN timespan ts ON sm.utc_date::timestamp without time zone = ts._date AND sm.asset_id = ts.asset_id))
  ORDER BY asset_id, _date;

----------------------------------
-- SOON Spot Promotion 
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_promotion
(		
    id BIGSERIAL,
		blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
		transfer_id BIGINT NOT NULL,
		tx_id TEXT NOT NULL,
		promotion_type TEXT NOT NULL,
		promotion_object TEXT NOT NULL,
    promotion_object_id TEXT NOT NULL,
		promotion_end_timestamp BIGINT,    
    active boolean NOT NULL,
    PRIMARY KEY (id)
)

TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_promotion_poi
    ON public.soonmarket_promotion USING btree
    (promotion_object_id, promotion_object)
    TABLESPACE pg_default;

--

CREATE VIEW soonmarket_promotion_stats_v as
SELECT 
t1.minted - t1.burned AS circulating,
t1.burned AS used,
t2.featured
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
	WHERE edition_size != 1 AND template_id=51066
	GROUP BY template_id,edition_size,creator) t1
LEFT JOIN LATERAL (SELECT COUNT(*) AS featured FROM soonmarket_promotion WHERE active AND promotion_type='silver')t2 ON TRUE;
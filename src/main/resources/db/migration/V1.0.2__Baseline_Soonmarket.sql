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
    has_kyc boolean,
    has_image boolean,
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

CREATE TABLE IF NOT EXISTS public.nft_watch_blacklist
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
    reviewer TEXT NOT NULL,
    reviewer_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

CREATE TABLE IF NOT EXISTS public.nft_watch_shielding
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
		reviewer TEXT NOT NULL,
    reviewer_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

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
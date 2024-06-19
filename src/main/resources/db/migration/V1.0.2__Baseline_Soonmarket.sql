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
-- account notifications 
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_notification
(    
		id bigserial,
    global_sequence bigint,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    action_id bigint NOT NULL,
    action_type text NOT NULL,
    account text NOT NULL,
    acknowledged boolean NOT NULL DEFAULT false,
    acknowledged_date bigint,
    PRIMARY KEY (global_sequence,action_type,account)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS soonmarket_notification_account
    ON public.soonmarket_notification USING btree
    (account ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS soonmarket_notification_ts
    ON public.soonmarket_notification USING btree
    (block_timestamp, global_sequence)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS soonmarket_notification_action_type
    ON public.soonmarket_notification USING btree
    (action_type)
    TABLESPACE pg_default;				

----------------------------------
-- account 
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_profile
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    has_kyc boolean DEFAULT false,
    has_image boolean DEFAULT false,
    account TEXT NOT NULL,
		bio TEXT,
		has_banner boolean,
		num_followers int,
		kyc_level text,
		kyc_provider text,
		kyc_date bigint,
		kyc_last_updated bigint,
		kyc_updated_by text,
    PRIMARY KEY (account)
)
TABLESPACE pg_default;

----------------------------------
-- blacklisting / shielding tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.soonmarket_internal_shielding
(
		id bigserial,
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
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NOT NULL,
    reporter_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE TABLE IF NOT EXISTS public.t_audit_reset_log
(
		id bigserial PRIMARY KEY,		
    blocknum bigint NOT NULL,
    timestamp bigint NOT NULL,
		context text NOT NULL,
    reset_type text NULL,    
    details text NULL,		
    clean_database boolean NOT NULL,
		clean_after_blocknum bigint NOT NULL
)
TABLESPACE pg_default;

--

CREATE TABLE IF NOT EXISTS public.nft_watch_blacklist
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NULL,
    reporter_comment TEXT NULL,
    reviewer TEXT NULL,
    reviewer_comment TEXT NULL,
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

-- 

CREATE TABLE IF NOT EXISTS public.nft_watch_shielding
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id TEXT NOT NULL,
    reporter TEXT NULL,
		reporter_comment TEXT NULL,		
    reviewer TEXT NULL,
		reviewer_comment TEXT NULL,		
		report_cid TEXT NULL,
		skip_basic_check BOOLEAN NULL,
		skip_reason TEXT NULL,    
    PRIMARY KEY (collection_id)
)
TABLESPACE pg_default;

--

CREATE TABLE IF NOT EXISTS public.t_audit_event_log
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
		global_sequence bigint PRIMARY KEY,
    transaction_id text NOT NULL,    
    type text NOT NULL,		
    data jsonb NULL    
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_t_audit_event_log_type
    ON public.t_atomicassets_event_log USING btree
    (type ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_t_audit_event_log_type_data
    ON public.t_atomicassets_event_log USING gin
    (data)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.t_audit_event_log IS 'Store all raw actions';


-- 

CREATE OR REPLACE VIEW soonmarket_collection_audit_info_v AS
SELECT                                                                            
t1.collection_id,                                                                 
CASE WHEN b1.collection_id IS NOT NULL or b2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS blacklisted,
COALESCE(b1.block_timestamp,b2.block_timestamp) AS blacklist_date,
COALESCE(b1.reviewer_comment,b2.reporter_comment) AS blacklist_reason,
CASE WHEN b1.reviewer is not null THEN 'NFT Watch DAO' WHEN b2.reporter is not null THEN 'Soon.Market' ELSE null END AS blacklist_actor,
CASE WHEN s1.collection_id IS NOT NULL or s2.collection_id IS NOT NULL THEN TRUE ELSE FALSE END AS shielded,
COALESCE(s1.block_timestamp,s2.block_timestamp) AS shielding_date,
CASE WHEN s1.reviewer is not null THEN 'NFT Watch DAO' WHEN s2.reporter is not null THEN 'Soon.Market' ELSE null END AS shielding_actor,
COALESCE(s1.reporter,s2.reporter) as reporter,
s1.skip_basic_check,
s1.skip_reason,
s1.report_cid,
s1.reviewer
FROM atomicassets_collection t1                                                   
LEFT JOIN nft_watch_blacklist b1 ON t1.collection_id = b1.collection_id 
LEFT JOIN soonmarket_internal_blacklist b2 ON t1.collection_id = b2.collection_id
LEFT JOIN nft_watch_shielding s1 ON t1.collection_id = s1.collection_id 
LEFT JOIN soonmarket_internal_shielding s2 ON t1.collection_id = s2.collection_id;

-- Trigger function for deleting entries from blacklist / shielding

CREATE OR REPLACE FUNCTION audit_delete_on_update_collection_id_f()
RETURNS TRIGGER AS $$

BEGIN
   	IF NEW.collection_id IS NOT NULL AND NEW.reporter_comment = '__delete__' THEN
			RAISE WARNING '[% - collection_id %] got delete command for table %, removing entry',TG_NAME,NEW.collection_id,TG_TABLE_NAME;		
			EXECUTE format('DELETE FROM %I.%I WHERE collection_id = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME) USING OLD.collection_id;
			RETURN NULL;
    END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger definitions

CREATE OR REPLACE TRIGGER nft_watch_shielding_update_collection_id_tr
BEFORE UPDATE ON public.nft_watch_shielding
FOR EACH ROW EXECUTE FUNCTION audit_delete_on_update_collection_id_f();

CREATE OR REPLACE TRIGGER nft_watch_blacklist_update_collection_id_tr
BEFORE UPDATE ON public.nft_watch_blacklist
FOR EACH ROW EXECUTE FUNCTION audit_delete_on_update_collection_id_f();

CREATE OR REPLACE TRIGGER soonmarket_internal_shielding_update_collection_id_tr
BEFORE UPDATE ON public.soonmarket_internal_shielding
FOR EACH ROW EXECUTE FUNCTION audit_delete_on_update_collection_id_f();

CREATE OR REPLACE TRIGGER soonmarket_internal_blacklist_update_collection_id_tr
BEFORE UPDATE ON public.soonmarket_internal_blacklist
FOR EACH ROW EXECUTE FUNCTION audit_delete_on_update_collection_id_f();

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
    (LEFT(er.utc_date, 10) || ' 00:00:00')::varchar(64) AS utc_date,
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
		blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,		
		tx_id TEXT NOT NULL,
		promotion_type TEXT NOT NULL,
		promotion_object TEXT NOT NULL,
    promotion_object_id TEXT NOT NULL,
		promotion_end_timestamp BIGINT,
		promoted_by TEXT,
		global_sequence BIGINT,
    PRIMARY KEY (global_sequence)
)

TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_promotion_poi
    ON public.soonmarket_promotion USING btree
    (promotion_object_id, promotion_object)
    TABLESPACE pg_default;

--

CREATE OR REPLACE VIEW soonmarket_promotion_v as
	SELECT * FROM soonmarket_promotion 
	WHERE	promotion_end_timestamp >= floor(EXTRACT(epoch FROM now())) OR promotion_end_timestamp IS NULL;

COMMENT ON VIEW public.soonmarket_promotion_v IS 'Only active promtions filtered by promotion_end_timestamp - either has value (collection promotion) or has none while active (auction)';	

-- reset log for promotion

CREATE TABLE IF NOT EXISTS public.t_promotion_reset_log
(
		id bigserial PRIMARY KEY,		
    blocknum bigint NOT NULL,
    timestamp bigint NOT NULL,
		context text NOT NULL,
    reset_type text NULL,    
    details text NULL,		
    clean_database boolean NOT NULL,
		clean_after_blocknum bigint NOT NULL
)
TABLESPACE pg_default;

-- trigger to clean all atomicassets_ tables after clean_after_blocknum
CREATE OR REPLACE FUNCTION t_promotion_reset_log_clean_after_blocknum_f()
RETURNS TRIGGER AS $$
DECLARE
    t_table_name text;
    t_schema_name text;
    dynamic_sql text;
BEGIN
		RAISE WARNING '[% - blocknum %] Started Execution of trigger', TG_NAME, NEW.blocknum;

    t_schema_name := 'public';

    -- if clean_database is true
    IF NEW.clean_database THEN
				RAISE WARNING '[% - blocknum %] Clean_database set to %, deleting entries after blocknum %', TG_NAME, NEW.blocknum, NEW.clean_database,NEW.clean_after_blocknum;
        -- build dynamic SQL to delete entries from matching tables
        FOR t_table_name IN 
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name = 'soonmarket_promotion'
        LOOP
            dynamic_sql := 'DELETE FROM ' || t_schema_name || '.' || t_table_name || ' WHERE blocknum >= $1';
						RAISE WARNING '[%] executing delete statement %', TG_NAME, 'DELETE FROM ' || t_schema_name || '.' || t_table_name || ' WHERE blocknum >= ' || NEW.clean_after_blocknum;
            EXECUTE dynamic_sql USING NEW.clean_after_blocknum;
        END LOOP;
    END IF;

		RAISE WARNING '[% - blocknum %] Execution of trigger took % ms', TG_NAME, NEW.blocknum, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER t_promotion_reset_log_clean_after_blocknum_tr
AFTER INSERT ON t_promotion_reset_log
FOR EACH ROW
EXECUTE FUNCTION t_promotion_reset_log_clean_after_blocknum_f();

COMMENT ON TABLE public.t_promotion_reset_log IS 'Store reset events. Whenever an entry is added, the promotion table is cleared after the given blocknum, see similiary named trigger';

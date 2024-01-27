----------------------------------
-- default tables
----------------------------------	

CREATE TABLE IF NOT EXISTS public.atomicmarket_event_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    transaction_id text NOT NULL,    
    type text NOT NULL,		
    data jsonb NULL    
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS atomicmarket_event_log_type
    ON public.atomicmarket_event_log USING btree
    (type ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS atomicmarket_event_log_type_data
    ON public.atomicmarket_event_log USING gin
    (data)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.atomicmarket_event_log IS 'Store all raw actions';

CREATE TABLE IF NOT EXISTS public.atomicmarket_reset_log
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

-- trigger to clean all atomicmarket_ tables after clean_after_blocknum
CREATE OR REPLACE FUNCTION atomicmarket_reset_log_clean_after_blocknum_f()
RETURNS TRIGGER AS $$
DECLARE
    t_table_name text;
    t_schema_name text;
    dynamic_sql text;
BEGIN
    t_schema_name := 'public';

    -- if clean_database is true
    IF NEW.clean_database THEN
        -- build dynamic SQL to delete entries from matching tables
        FOR t_table_name IN 
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name LIKE 'atomicmarket_%' AND TABLE_TYPE = 'BASE TABLE' OR TABLE_NAME= 'realtime_event'
        LOOP
            dynamic_sql := 'DELETE FROM ' || t_schema_name || '.' || t_table_name || ' WHERE blocknum >= $1';
            EXECUTE dynamic_sql USING NEW.clean_after_blocknum;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER atomicmarket_reset_log_clean_after_blocknum_tr
AFTER INSERT ON atomicmarket_reset_log
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_reset_log_clean_after_blocknum_f();

COMMENT ON TABLE public.atomicmarket_reset_log IS 'Store reset events. Whenever an entry is added, the atomicmarket_ tables is cleared after the given blocknum, see similiary named trigger';

----------------------------------
-- config tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicmarket_token
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,       
		contract text NOT NULL,
		token text NOT NULL,
		precision SMALLINT NOT NULL,
		PRIMARY KEY (token)	
)
TABLESPACE pg_default;
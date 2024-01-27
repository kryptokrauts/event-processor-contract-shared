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
----------------------------------
-- sale tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicmarket_sale
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,       
		sale_id bigint NOT NULL,				
		offer_id bigint,
		primary_asset_id bigint,
		bundle boolean,
		bundle_size bigint,
		price double precision,
		token text,
		collection_fee double precision,
		seller text,		
		maker_marketplace text,		
		collection_id text, 
		PRIMARY KEY (sale_id)	
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_seller
    ON public.atomicmarket_sale USING btree
    (seller ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_bundle
    ON public.atomicmarket_sale USING btree
    (bundle)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicmarket_sale IS 'Store sales, every sale which has no corresponding entry in atomicmarket_sale_state is in listed state';		

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_sale_state
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,       
		sale_id bigint NOT NULL,		
		state smallint NOT NULL,
		maker_market_fee DOUBLE PRECISION,
		taker_market_fee DOUBLE PRECISION,
		buyer text NULL,		
		taker_marketplace text NULL,
		PRIMARY KEY (sale_id)	
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_state_state
    ON public.atomicmarket_sale_state USING btree
    (state)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicmarket_sale_state IS 'Store sale state change information';
COMMENT ON COLUMN public.atomicmarket_sale_state.state IS 'Sale state mapping: 2=cancelled, 3=sold';

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_sale_asset
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    sale_id bigint NOT NULL,
    index integer NOT NULL,
    asset_id bigint NOT NULL,
    template_id bigint,
    collection_id TEXT,
    PRIMARY KEY (sale_id, asset_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_asset_template_id
    ON public.atomicmarket_sale_asset USING btree
    (template_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_asset_sale_id
    ON public.atomicmarket_sale_asset USING btree
    (sale_id)
    TABLESPACE pg_default;
		
CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_asset_asset_id
    ON public.atomicmarket_sale_asset USING btree
    (asset_id)
    TABLESPACE pg_default;		

----------------------------------
-- auction tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicmarket_auction
(
    blocknum bigint,
    block_timestamp bigint,
    auction_id bigint NOT NULL,
    primary_asset_id bigint,
    bundle boolean,
    bundle_size integer,
    end_time bigint,
    price double precision,
    token TEXT NOT NULL,
    collection_fee double precision NOT NULL,
    maker_marketplace TEXT NOT NULL,
    seller TEXT NOT NULL,
    PRIMARY KEY (auction_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_seller
    ON public.atomicmarket_auction USING btree
    (seller ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_bundle
    ON public.atomicmarket_auction USING btree
    (bundle)
    TABLESPACE pg_default;	

COMMENT ON TABLE public.atomicmarket_auction IS 'Store auctions, every auction which has no corresponding entry in atomicmarket_auction_state is in open state';	

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_auction_state
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    auction_id bigint NOT NULL,
    state smallint,
    end_time bigint,
    winning_bid bigint,
		buyer TEXT,		
    maker_market_fee double precision,
    taker_market_fee double precision,
    taker_marketplace TEXT,    
    PRIMARY KEY (auction_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_state_state
    ON public.atomicmarket_auction_state USING btree
    (state)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicmarket_auction_state IS 'Store auction state change information';
COMMENT ON COLUMN public.atomicmarket_auction_state.state IS 'Sale state mapping: 2=cancelled, 3=finished with bids, 4=finished without bids';

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_auction_asset
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    auction_id bigint NOT NULL,
    index integer NOT NULL,
    asset_id bigint NOT NULL,
    template_id bigint,
    collection_id TEXT,
    PRIMARY KEY (auction_id, asset_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_asset_template_id
    ON public.atomicmarket_auction_asset USING btree
    (template_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_asset_auction_id
    ON public.atomicmarket_auction_asset USING btree
    (auction_id)
    TABLESPACE pg_default;
		
CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_asset_asset_id
    ON public.atomicmarket_auction_asset USING btree
    (asset_id)
    TABLESPACE pg_default;

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_event_auction_bid_log
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    current boolean NOT NULL,
    auction_id bigint NOT NULL,
    current_bid double precision,
    bid_number integer NOT NULL,
    updated_end_date bigint,
    bidder TEXT NOT NULL,
    taker_marketplace TEXT,
    PRIMARY KEY (auction_id, bid_number)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_event_auction_bid_log_current
    ON public.atomicmarket_event_auction_bid_log USING btree
    (current)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_event_auction_bid_log_auction_id
    ON public.atomicmarket_event_auction_bid_log USING btree
    (auction_id)
    TABLESPACE pg_default;		

----------------------------------
-- buyoffer tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicmarket_buyoffer
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    buyoffer_id bigint NOT NULL,
    primary_asset_id bigint,
    bundle boolean,
    bundle_size integer,
    price double precision,
    token TEXT,
    collection_fee double precision,
    maker_marketplace TEXT NOT NULL,
    seller TEXT,
    buyer TEXT,
    memo TEXT,
    PRIMARY KEY (buyoffer_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_seller
    ON public.atomicmarket_buyoffer USING btree
    (seller ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_bundle
    ON public.atomicmarket_buyoffer USING btree
    (bundle)
    TABLESPACE pg_default;	

COMMENT ON TABLE public.atomicmarket_buyoffer IS 'Store buyoffers, every buyoffer which has no corresponding entry in atomicmarket_buyoffer_state is in created state';	

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_buyoffer_state
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    buyoffer_id bigint,
    state smallint,
    taker_marketplace TEXT,
    maker_market_fee double precision,
    taker_market_fee double precision,
    decline_memo TEXT
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_state_state
    ON public.atomicmarket_buyoffer_state USING btree
    (state)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicmarket_buyoffer_state IS 'Store buyoffer state change information';
COMMENT ON COLUMN public.atomicmarket_buyoffer_state.state IS 'Sale state mapping: 1=declined, 2=cancelled, 3=accepted/sold';

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_buyoffer_asset
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    buyoffer_id bigint NOT NULL,
    index integer NOT NULL,
    asset_id bigint NOT NULL,
    template_id bigint,
    PRIMARY KEY (buyoffer_id, asset_id)
)
TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_asset_template_id
    ON public.atomicmarket_buyoffer_asset USING btree
    (template_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_asset_buyoffer_id
    ON public.atomicmarket_buyoffer_asset USING btree
    (buyoffer_id)
    TABLESPACE pg_default;
		
CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_asset_asset_id
    ON public.atomicmarket_buyoffer_asset USING btree
    (asset_id)
    TABLESPACE pg_default;

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

CREATE INDEX IF NOT EXISTS idx_atomicmarket_event_log_type
    ON public.atomicmarket_event_log USING btree
    (type ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_event_log_type_data
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
            WHERE table_name LIKE 'atomicmarket_%' AND TABLE_TYPE = 'BASE TABLE' OR TABLE_NAME= 'soonmarket_realtime_event'
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

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_config
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
		maker_fee double precision NULL,
		taker_fee double precision NULL,
    version text NULL,     
		auction_min_duration_seconds integer NULL,
		auction_max_duration_seconds integer NULL,
		auction_min_bid_increase double precision NULL,
		auction_reset_duration_seconds integer NULL,
		PRIMARY KEY (id)			
)
TABLESPACE pg_default;

-- trigger to fill fields from previous dataset
CREATE OR REPLACE FUNCTION atomicmarket_config_fill_with_previous_if_null_f()
RETURNS TRIGGER AS $$
DECLARE
    prev_row public.atomicmarket_config;
BEGIN
    -- Retrieve the values from the previous row
    SELECT *
    INTO prev_row
    FROM public.atomicmarket_config
    WHERE id = (SELECT max(id) FROM public.atomicmarket_config WHERE id < NEW.id);

    -- Check each column and replace with the previous row's value if it is not NULL
    NEW.blocknum := COALESCE(NEW.blocknum, prev_row.blocknum);
    NEW.block_timestamp := COALESCE(NEW.block_timestamp, prev_row.block_timestamp);
    NEW.maker_fee := COALESCE(NEW.maker_fee, prev_row.maker_fee);
    NEW.taker_fee := COALESCE(NEW.taker_fee, prev_row.taker_fee);
    NEW.version := COALESCE(NEW.version, prev_row.version);
    NEW.auction_min_duration_seconds := COALESCE(NEW.auction_min_duration_seconds, prev_row.auction_min_duration_seconds);
    NEW.auction_max_duration_seconds := COALESCE(NEW.auction_max_duration_seconds, prev_row.auction_max_duration_seconds);
    NEW.auction_min_bid_increase := COALESCE(NEW.auction_min_bid_increase, prev_row.auction_min_bid_increase);
    NEW.auction_reset_duration_seconds := COALESCE(NEW.auction_reset_duration_seconds, prev_row.auction_reset_duration_seconds);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER atomicmarket_config_fill_with_previous_if_null_tr
BEFORE INSERT ON atomicmarket_config
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_config_fill_with_previous_if_null_f();

COMMENT ON TABLE public.atomicmarket_config IS 'Store global market config';

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_marketplace
(		
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
	 	name text NOT NULL,     
		creator text,
		PRIMARY KEY (name)			
)
TABLESPACE pg_default;

COMMENT ON TABLE public.atomicmarket_config IS 'Store registered marketplaces';
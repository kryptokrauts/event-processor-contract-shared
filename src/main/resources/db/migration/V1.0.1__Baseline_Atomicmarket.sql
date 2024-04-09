----------------------------------
-- trigger functions
----------------------------------

-- trigger function to fill template_id and collection_id in market_asset tables
CREATE OR REPLACE FUNCTION atomicmarket_asset_fill_ids_f()
RETURNS TRIGGER AS $$
DECLARE
    _template_id bigint;
		_collection_id text;
BEGIN
    -- Retrieve the values from the previous row
    SELECT template_id, collection_id INTO _template_id,_collection_id FROM public.atomicassets_asset WHERE asset_id = NEW.asset_id;

    -- set template_id and collection_id
    NEW.template_id := _template_id;
    NEW.collection_id := _collection_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger function set auction bid number and update end time
CREATE OR REPLACE FUNCTION atomicmarket_auction_bid_log_f()
RETURNS TRIGGER AS $$
DECLARE
    _bid_number int;
		_end_time DOUBLE PRECISION;
		_updated_end_time DOUBLE PRECISION;
		_now BIGINT;
		_auction_reset_ms BIGINT;
BEGIN
    -- Retrieve new highest bid number
    SELECT COALESCE(max(bid_number)+1,1) INTO _bid_number FROM public.atomicmarket_event_auction_bid_log where auction_id = NEW.auction_id;
		-- get config
		SELECT auction_reset_duration_seconds*1000 INTO _auction_reset_ms FROM public.atomicmarket_config order by version desc limit 1;
		-- retrieve end times for potential bump
		SELECT end_time into _end_time from public.atomicmarket_auction where auction_id = NEW.auction_id;
		SELECT max(updated_end_time) INTO _updated_end_time FROM public.atomicmarket_event_auction_bid_log where auction_id = NEW.auction_id;
		SELECT FLOOR((extract(epoch from NOW() at time zone 'utc'))*1000) into _now;

    -- set fees
    NEW.bid_number := _bid_number;
    NEW.updated_end_time := CASE WHEN (GREATEST(_updated_end_time,_end_time)-_now)<=_auction_reset_ms THEN _now+_auction_reset_ms ELSE NULL END;
		NEW.current := true;

		-- set other bids current value to false
		UPDATE atomicmarket_event_auction_bid_log SET current = false WHERE auction_id = NEW.auction_id AND global_sequence != NEW.global_sequence;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger function to fill maker and taker market fees from current config
CREATE OR REPLACE FUNCTION atomicmarket_state_fill_mtfees_f()
RETURNS TRIGGER AS $$
DECLARE
    _makerfee DOUBLE PRECISION;
		_takerfee DOUBLE PRECISION;
BEGIN
    -- Retrieve the values from the previous row
    SELECT maker_fee,taker_fee INTO _makerfee,_takerfee FROM public.atomicmarket_config order by version desc limit 1;

    -- set fees
    NEW.maker_market_fee := _makerfee;
    NEW.taker_market_fee := _takerfee;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger function to fill auction claim log with previous
CREATE OR REPLACE FUNCTION atomicmarket_auction_claim_log_fill_f()
RETURNS TRIGGER AS $$
DECLARE
    _claimed_by_buyer BOOLEAN;
	_claimed_by_seller BOOLEAN;
BEGIN
    -- Retrieve the values from the previous row
    SELECT 
		claimed_by_buyer,
		claimed_by_seller 
	INTO _claimed_by_buyer,_claimed_by_seller 
	FROM public.atomicmarket_auction_claim_log where auction_id=NEW.auction_Id and current;
	    
  	NEW.claimed_by_buyer := COALESCE(NEW.claimed_by_buyer, _claimed_by_buyer);
		NEW.claimed_by_seller := COALESCE(NEW.claimed_by_seller, _claimed_by_seller);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
		bundle_size int,
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

CREATE INDEX IF NOT EXISTS idx_atomicmarket_sale_state_sale_id_buyer
    ON public.atomicmarket_sale_state USING btree
    (sale_id,buyer)
    TABLESPACE pg_default;	

-- add trigger for market fees
CREATE OR REPLACE TRIGGER atomicmarket_sale_state_fill_mtfees_tr
BEFORE INSERT ON atomicmarket_sale_state
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_state_fill_mtfees_f();							

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

-- add trigger to set template_id / collection_id

CREATE OR REPLACE TRIGGER atomicmarket_sale_asset_fill_ids_tr
BEFORE INSERT ON atomicmarket_sale_asset
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_asset_fill_ids_f();			

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
    bundle_size int,
		start_time bigint,
    end_time bigint,
		duration bigint,
    price double precision,
    token TEXT NOT NULL,
    collection_fee double precision NOT NULL,
    maker_marketplace TEXT NULL,
		collection_id text,
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
    winning_bid double precision NULL,
		buyer TEXT NULL,		
    maker_market_fee double precision NULL,
    taker_market_fee double precision NULL,
    taker_marketplace TEXT NULL,    
    PRIMARY KEY (auction_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_state_state
    ON public.atomicmarket_auction_state USING btree
    (state)
    TABLESPACE pg_default;			

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_state_auctionid_state
    ON public.atomicmarket_auction_state USING btree
    (auction_id,state)
    TABLESPACE pg_default;

-- trigger to omit setting state to 2 when state was already set to 4 (cancelled without bids)
-- because an onchain event cancelauct will be sent when the owner returns the asset after an unsuccessful auction
CREATE OR REPLACE FUNCTION atomicmarket_auction_state_cancel_check_f()
RETURNS TRIGGER AS $$
BEGIN
	-- if auction state is already 4 (ended without bids) we do not set the cancelauct event
	-- when the owner triggers the asset claim of the unsuccessful auction
  IF NEW.state = 2 AND OLD.state != 2 THEN
		NEW.state = OLD.state;
	END IF;
	
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER atomicmarket_auction_state_cancel_check_tr
BEFORE UPDATE ON atomicmarket_auction_state
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_auction_state_cancel_check_f();		

COMMENT ON TABLE public.atomicmarket_auction_state IS 'Store auction state change information';
COMMENT ON COLUMN public.atomicmarket_auction_state.state IS 'Auction state mapping: 2=cancelled, 3=finished with bids, 4=finished without bids';

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

-- add trigger to set template_id / collection_id

CREATE OR REPLACE TRIGGER atomicmarket_auction_asset_fill_ids_tr
BEFORE INSERT ON atomicmarket_auction_asset
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_asset_fill_ids_f();			

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_event_auction_bid_log
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    current boolean NOT NULL,
    auction_id bigint NOT NULL,
		global_sequence bigint NOT NULL,
    current_bid double precision,
    bid_number integer NOT NULL,
    updated_end_time bigint,
    bidder TEXT NOT NULL,
    taker_marketplace TEXT,
    PRIMARY KEY (global_sequence)
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

-- add trigger to set bid number and potential bump date
CREATE OR REPLACE TRIGGER atomicmarket_auction_bid_log_tr
BEFORE INSERT ON atomicmarket_event_auction_bid_log
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_auction_bid_log_f();	

--

CREATE TABLE IF NOT EXISTS public.atomicmarket_auction_claim_log
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    auction_id bigint NOT NULL,
		current boolean,
		claimed_by_seller boolean null,
    claimed_by_buyer boolean null,
    PRIMARY KEY (id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_claim_log_current
    ON public.atomicmarket_auction_claim_log USING btree
    (current)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_auction_claim_log_auction_id
    ON public.atomicmarket_auction_claim_log USING btree
    (auction_id)
    TABLESPACE pg_default;

-- add trigger to update current flag
CREATE TRIGGER atomicmarket_event_auction_claim_log_tr
BEFORE INSERT ON public.atomicmarket_auction_claim_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('auction_id');	

CREATE TRIGGER atomicmarket_auction_claim_log_fill_tr
BEFORE INSERT ON public.atomicmarket_auction_claim_log
FOR EACH ROW EXECUTE FUNCTION atomicmarket_auction_claim_log_fill_f();


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
    maker_marketplace TEXT NULL,
		collection_id text,
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
    decline_memo TEXT,
    PRIMARY KEY (buyoffer_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicmarket_buyoffer_state_state
    ON public.atomicmarket_buyoffer_state USING btree
    (state)
    TABLESPACE pg_default;	

-- add trigger to fill maker / taker market fees
CREATE OR REPLACE TRIGGER atomicmarket_buyoffer_state_fill_mtfees_tr
BEFORE INSERT ON atomicmarket_buyoffer_state
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_state_fill_mtfees_f();					

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
		collection_id text,
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

-- add trigger

CREATE OR REPLACE TRIGGER atomicmarket_buyoffer_asset_fill_ids_tr
BEFORE INSERT ON atomicmarket_buyoffer_asset
FOR EACH ROW
EXECUTE FUNCTION atomicmarket_asset_fill_ids_f();			

----------------------------------
-- default tables
----------------------------------	

CREATE TABLE IF NOT EXISTS public.t_atomicmarket_event_log
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

CREATE INDEX IF NOT EXISTS idx_t_atomicmarket_event_log_type
    ON public.t_atomicmarket_event_log USING btree
    (type ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_t_atomicmarket_event_log_type_data
    ON public.t_atomicmarket_event_log USING gin
    (data)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.t_atomicmarket_event_log IS 'Store all raw actions';

CREATE TABLE IF NOT EXISTS public.t_atomicmarket_reset_log
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
CREATE OR REPLACE FUNCTION t_atomicmarket_reset_log_clean_after_blocknum_f()
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
            WHERE table_name LIKE 'atomicmarket_%' AND TABLE_TYPE = 'BASE TABLE' OR TABLE_NAME= 'soonmarket_realtime_event'
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

CREATE OR REPLACE TRIGGER t_atomicmarket_reset_log_clean_after_blocknum_tr
AFTER INSERT ON t_atomicmarket_reset_log
FOR EACH ROW
EXECUTE FUNCTION t_atomicmarket_reset_log_clean_after_blocknum_f();

COMMENT ON TABLE public.t_atomicmarket_reset_log IS 'Store reset events. Whenever an entry is added, the atomicmarket_ tables is cleared after the given blocknum, see similiary named trigger';

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
----------------------------------
-- default tables
----------------------------------	

CREATE TABLE IF NOT EXISTS public.atomicassets_event_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    transaction_id text NOT NULL,    
    type text NOT NULL,		
    data jsonb NULL    
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_event_log_type
    ON public.atomicassets_event_log USING btree
    (type ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_event_log_type_data
    ON public.atomicassets_event_log USING gin
    (data)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.atomicassets_event_log IS 'Store all raw actions';

CREATE TABLE IF NOT EXISTS public.atomicassets_reset_log
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
CREATE OR REPLACE FUNCTION atomicassets_reset_log_clean_after_blocknum_f()
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
            WHERE table_name LIKE 'atomicassets_%' AND TABLE_TYPE = 'BASE TABLE' OR TABLE_NAME= 'soonmarket_realtime_event'
        LOOP
            dynamic_sql := 'DELETE FROM ' || t_schema_name || '.' || t_table_name || ' WHERE blocknum >= $1';
            EXECUTE dynamic_sql USING NEW.clean_after_blocknum;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER atomicassets_reset_log_clean_after_blocknum_tr
AFTER INSERT ON atomicassets_reset_log
FOR EACH ROW
EXECUTE FUNCTION atomicassets_reset_log_clean_after_blocknum_f();

COMMENT ON TABLE public.atomicassets_reset_log IS 'Store reset events. Whenever an entry is added, the atomicassets_ tables is cleared after the given blocknum, see similiary named trigger';

CREATE TABLE IF NOT EXISTS public.soonmarket_realtime_event
(
		id bigserial PRIMARY KEY,		
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
		asset_id bigint NULL,
		template_id bigint NULL,
		collection_id text NOT NULL,
		context text NOT NULL,
    type text NOT NULL,    
    data jsonb NULL
)
TABLESPACE pg_default;

-- Create a function to extract and convert the "assetName" field to tsvector
CREATE FUNCTION extract_assetname(data jsonb) RETURNS tsvector AS $$
BEGIN
  RETURN to_tsvector(data->>'assetName');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create a GIN index on the tsvector field generated by the function
CREATE INDEX idx_soonmarket_realtime_event_assetname ON soonmarket_realtime_event USING gin (extract_assetname(data));

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_event_type
    ON public.soonmarket_realtime_event USING btree
    (type)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_event_block_timestamp
    ON public.soonmarket_realtime_event USING btree
    (block_timestamp)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_asset_id
    ON public.soonmarket_realtime_event USING btree
    (asset_id)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_template_id
    ON public.soonmarket_realtime_event USING btree
    (template_id)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_asset_template_collection_id_block_ts
    ON public.soonmarket_realtime_event USING btree
    (asset_id,template_id,collection_id,block_timestamp)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_soonmarket_realtime_asset_data
    ON public.soonmarket_realtime_event USING gin
    (data)
    TABLESPACE pg_default;													

COMMENT ON TABLE public.soonmarket_realtime_event IS 'Stores realtime events for retrieving historic entries';

----------------------------------
-- offer tables
----------------------------------	

CREATE TABLE IF NOT EXISTS public.atomicassets_offer
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,  
    offer_id bigint,
    sender text NOT NULL,
    sender_asset_ids text[],
    receiver text NOT NULL,
    receiver_asset_ids text[] ,
    memo text NULL,
		PRIMARY KEY (offer_id)
    
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_offer_blocknum
    ON public.atomicassets_offer USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_offer_memo
    ON public.atomicassets_offer USING btree
    (memo ASC NULLS LAST)
    TABLESPACE pg_default;

COMMENT ON TABLE public.atomicassets_offer IS 'Store atomicassets offers';			

CREATE TABLE IF NOT EXISTS public.atomicassets_offer_state_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    offer_id bigint NOT NULL,
    state text NOT NULL		
)
TABLESPACE pg_default;					

CREATE INDEX IF NOT EXISTS idx_atomicassets_offer_state_log_state
    ON public.atomicassets_offer_state_log USING btree
    (state ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_offer_state_log_offer_id
    ON public.atomicassets_offer_state_log USING btree
    (offer_id ASC NULLS LAST)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicassets_offer_state_log IS 'Store state changes on atomicassets offers as log';

----------------------------------
-- transfer tables
----------------------------------		
CREATE TABLE IF NOT EXISTS public.atomicassets_transfer
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    transfer_id bigserial,
    sender text NOT NULL,
    receiver text NOT NULL,
    asset_ids text[] ,
    memo text NULL,
		PRIMARY KEY(transfer_id)
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_transfer_blocknum
    ON public.atomicassets_transfer USING btree
    (blocknum DESC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_transfer_memo
    ON public.atomicassets_transfer USING btree
    (memo)
    TABLESPACE pg_default;

COMMENT ON TABLE public.atomicassets_transfer IS 'Store all "real" transfers (without market interaction)';

----------------------------------
-- collection tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicassets_collection
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    collection_id text PRIMARY KEY,
		creator text NOT NULL
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_creator
    ON public.atomicassets_collection USING btree
    (creator ASC NULLS LAST)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.atomicassets_collection IS 'Store base collection. Collection entries are only persisted once';

CREATE TABLE IF NOT EXISTS public.atomicassets_collection_data_log
(
		id bigserial PRIMARY KEY,
		blocknum bigint NOT NULL,
		block_timestamp bigint NOT NULL,  
		collection_id text NOT NULL,		
		current boolean,
		category text NULL,
		name text NULL, 		
		description text NULL,
		image text NULL,
		data jsonb NULL	
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_data_log_blocknum
    ON public.atomicassets_collection_data_log USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_data_log_collection_id
    ON public.atomicassets_collection_data_log USING btree
    (collection_id desc NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_data_log_name
    ON public.atomicassets_collection_data_log USING btree
    (name asc NULLS LAST)
    TABLESPACE pg_default;			

CREATE INDEX IF NOT EXISTS idx_collection_data_log_data
    ON public.atomicassets_collection_data_log USING gin
    (data)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_collection_data_log_current
    ON public.atomicassets_collection_data_log USING btree
    (current)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_data_log_category
    ON public.atomicassets_collection_data_log USING btree
    (category asc NULLS LAST)
    TABLESPACE pg_default;						

COMMENT ON TABLE public.atomicassets_collection_data_log IS 'Store collection data. Every time the data is updated, a new entry is persisted';

CREATE TABLE IF NOT EXISTS public.atomicassets_collection_royalty_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,  
    collection_id text NOT NULL,
		current boolean,
		royalty DOUBLE PRECISION NOT NULL		
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_royalty_log_blocknum
    ON public.atomicassets_collection_royalty_log USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_royalty_log_collection_id
    ON public.atomicassets_collection_royalty_log USING btree
    (collection_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_collection_royalty_log_current
    ON public.atomicassets_collection_royalty_log USING btree
    (current)
    TABLESPACE pg_default;		

COMMENT ON TABLE public.atomicassets_collection_royalty_log IS 'Store collection royalty. Every time the royalty is updated, a new entry is persisted';		

CREATE TABLE IF NOT EXISTS public.atomicassets_collection_account_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,  
		collection_id text NOT NULL,   
		current boolean,
		allow_notify boolean NOT NULL,
		authorized_accounts text[] NULL,
		notify_accounts text[] NULL	
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_account_log_blocknum
    ON public.atomicassets_collection_account_log USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_collection_account_log_collection_id
    ON public.atomicassets_collection_account_log USING btree
    (collection_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_collection_account_log_current
    ON public.atomicassets_collection_account_log USING btree
    (current)
    TABLESPACE pg_default;		


COMMENT ON TABLE public.atomicassets_collection_account_log IS 'Store collection accounts. Every time the collection related accounts are updated, a new entry is persisted';				

----------------------------------
-- schema tables
----------------------------------	

CREATE TABLE IF NOT EXISTS public.atomicassets_schema
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL, 
    schema_id text NOT NULL,
		schema_name text NULL,
    creator text NOT NULL,
    collection_id text NOT NULL,
		PRIMARY KEY (schema_id,collection_id)		
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_schema_name
    ON public.atomicassets_schema USING btree
    (schema_name ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_schema_creator
    ON public.atomicassets_schema USING btree
    (creator ASC NULLS LAST)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_schema_collection_id
    ON public.atomicassets_schema USING btree
    (collection_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_schema_schema_id
    ON public.atomicassets_schema USING btree
    (schema_id ASC NULLS LAST)
    TABLESPACE pg_default;

COMMENT ON TABLE public.atomicassets_schema IS 'Store general schema information';

CREATE TABLE IF NOT EXISTS public.atomicassets_schema_format_log
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    schema_id text NOT NULL,
		current boolean,
		collection_id text NOT NULL,
		editor text NULL,
		format jsonb NULL,		
		PRIMARY KEY(id)		
)
TABLESPACE pg_default;	

COMMENT ON TABLE public.atomicassets_schema_format_log IS 'Store latest format for schema. On schema update existing format will be merged, see trigger idx_schema_format_log_schema_merge_tr';

CREATE INDEX IF NOT EXISTS idx_schema_format_log_blocknum
    ON public.atomicassets_schema_format_log USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_schema_format_log_schema_id_collection_id
    ON public.atomicassets_schema_format_log USING btree
    (schema_id,collection_id ASC NULLS LAST)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicassets_schema_format_log_current
    ON public.atomicassets_schema_format_log USING btree
    (current)
    TABLESPACE pg_default;						

CREATE OR REPLACE FUNCTION atomicassets_schema_format_log_schema_merge_f()
RETURNS TRIGGER AS $$
BEGIN  	
		NEW.format := (
			SELECT jsonb_agg(DISTINCT value)
			FROM (
  			SELECT jsonb_array_elements(coalesce(log.format, '[]'::jsonb)) AS value
            FROM public.atomicassets_schema_format_log log
            WHERE log.collection_id = NEW.collection_id
              AND log.schema_id = NEW.schema_id
              AND log.blocknum = (
                  SELECT MAX(blocknum)
                  FROM public.atomicassets_schema_format_log
                  WHERE collection_id = NEW.collection_id
                    AND schema_id = NEW.schema_id
              )
  			UNION
  			SELECT jsonb_array_elements(NEW.format) AS value
			) AS DATA);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER atomicassets_schema_format_log_schema_merge_tr
BEFORE INSERT ON public.atomicassets_schema_format_log
FOR EACH ROW EXECUTE FUNCTION atomicassets_schema_format_log_schema_merge_f();		

----------------------------------
-- template tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicassets_template
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    template_id bigint NOT NULL,
		schema_id text NOT NULL,
		collection_id text NOT NULL,    
		creator text NOT NULL,
    transferable boolean NOT NULL,
		burnable boolean NOT NULL,
		initial_max_supply bigint NULL,
		name text NULL,
		description text NULL,
		media text NULL,
		media_type text NULL,	
		media_preview text NULL,
		immutable_data jsonb NULL,
		PRIMARY KEY (template_id)		
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_template_creator
    ON public.atomicassets_template USING btree
    (creator ASC NULLS LAST)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_template_collection_id
    ON public.atomicassets_template USING btree
    (collection_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_template_schema_id
    ON public.atomicassets_template USING btree
    (schema_id ASC NULLS LAST)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_template_immutable_data
    ON public.atomicassets_template USING gin
    (immutable_data)
    TABLESPACE pg_default;	

COMMENT ON TABLE public.atomicassets_template IS 'Store general information about template (edition NFTs)';		

CREATE TABLE IF NOT EXISTS public.atomicassets_template_state
(
		blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,  
    template_id bigint NOT NULL,		
		editor text NULL,
		locked_at_supply bigint NULL,		
		locked boolean NOT NULL,
		PRIMARY KEY(template_id)
)
TABLESPACE pg_default;

COMMENT ON TABLE public.atomicassets_template_state IS 'Store template state information, if locked max_supply is set via trigger';

CREATE INDEX IF NOT EXISTS idx_template_state_blocknum
    ON public.atomicassets_template_state USING btree
    (blocknum ASC NULLS LAST)
    TABLESPACE pg_default;

-- automatically set max_supply to number of minted edition NFTs
CREATE OR REPLACE FUNCTION atomicassets_template_state_set_new_locked_at_supply_f()
RETURNS TRIGGER AS $$
BEGIN  	
		NEW.locked_at_supply := (SELECT COUNT(*) FROM public.atomicassets_asset WHERE template_id = NEW.template_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER atomicassets_template_state_set_new_locked_at_supply_tr
BEFORE INSERT ON public.atomicassets_template_state
FOR EACH ROW EXECUTE FUNCTION atomicassets_template_state_set_new_locked_at_supply_f();

COMMENT ON TRIGGER atomicassets_template_state_set_new_locked_at_supply_tr ON public.atomicassets_template_state
    IS 'Set the max_supply based on the number of assets existing for this template_id by using a function named similiarly';

----------------------------------
-- asset tables
----------------------------------

CREATE TABLE IF NOT EXISTS public.atomicassets_asset
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,   
    asset_id bigint NOT NULL,
		serial bigint NULL,
		template_id bigint NULL,
		schema_id text NOT NULL,
		collection_id text NOT NULL,    
		minter text NOT NULL,
		receiver text NOT NULL,
		immutable_data jsonb NULL,		
		PRIMARY KEY (asset_id)		
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_asset_receiver
    ON public.atomicassets_asset USING btree
    (receiver ASC NULLS LAST)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_asset_collection_id
    ON public.atomicassets_asset USING btree
    (collection_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_asset_template_id
    ON public.atomicassets_asset USING btree
    (template_id ASC NULLS LAST)
    TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_asset_immutable_data
    ON public.atomicassets_asset USING gin
    (immutable_data)
    TABLESPACE pg_default;

-- trigger for automatically filling the serial for this edition NFT
-- if template_id is null it is a real 1/1 and we set serial to 1
CREATE OR REPLACE FUNCTION atomicassets_asset_auto_increment_serial_f()
RETURNS TRIGGER AS $$
BEGIN
		IF NEW.template_id IS NOT NULL THEN
    	NEW.serial := COALESCE((SELECT MAX(serial) FROM public.atomicassets_asset WHERE template_id = NEW.template_id), 0) + 1;
		ELSE
			NEW.serial := 1;
		END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER atomicassets_asset_serial_tr
BEFORE INSERT ON public.atomicassets_asset
FOR EACH ROW EXECUTE FUNCTION atomicassets_asset_auto_increment_serial_f();

COMMENT ON TABLE public.atomicassets_asset IS 'Store general asset (NFT) information';
COMMENT ON COLUMN public.atomicassets_asset.receiver IS 'Store account who received this NFT';
COMMENT ON COLUMN public.atomicassets_asset.minter IS 'User or contract which was used to mint the NFT';

CREATE TABLE IF NOT EXISTS public.atomicassets_asset_data
(
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,   
    asset_id bigint NOT NULL,	
		transferable boolean NOT NULL default TRUE,
		burnable boolean NOT NULL default TRUE,	
		name text NULL,
		description text NULL,
		media text NULL,
		media_type text NULL,	
		media_preview text NULL,		
		PRIMARY KEY (asset_id)		
)
TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_data_name
    ON public.atomicassets_asset_data USING btree
    (name ASC NULLS LAST)
    TABLESPACE pg_default;

COMMENT ON COLUMN public.atomicassets_asset_data.transferable IS '1:1 NFTs without template are always transferable';
COMMENT ON COLUMN public.atomicassets_asset_data.burnable IS '1:1 NFTs without template are always burnable';
COMMENT ON TABLE public.atomicassets_asset_data IS 'Store most relevant fields in case of real 1:1 NFTs (without template). Externalized since all assets come with a template currently';

CREATE TABLE IF NOT EXISTS public.atomicassets_asset_data_log
(
		id bigserial PRIMARY KEY,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL,   
    asset_id bigint NOT NULL,		
		current boolean,
		mutable_data jsonb NULL,
		backed_tokens jsonb NULL		
)
TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_data_log_asset_id
    ON public.atomicassets_asset_data_log USING btree
    (asset_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_asset_data_log_mutable_data
    ON public.atomicassets_asset_data_log USING gin
    (mutable_data)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_data_log_current
    ON public.atomicassets_asset_data_log USING btree
    (current)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_data_log_asset_id_current
    ON public.atomicassets_asset_data_log USING btree
    (asset_id,current)
    TABLESPACE pg_default;			

COMMENT ON TABLE public.atomicassets_asset_data_log IS 'Store log of assets mutable data changes';

--

CREATE TABLE IF NOT EXISTS public.atomicassets_asset_owner_log
(
		id bigserial,
    blocknum bigint NOT NULL,
    block_timestamp bigint NOT NULL, 
    asset_id bigint NOT NULL,		
		current boolean,
		owner text NULL,
		burned boolean NOT NULL default FALSE,		
		PRIMARY KEY (id)
)
TABLESPACE pg_default;		

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_owner_log_asset_id
    ON public.atomicassets_asset_owner_log USING btree
    (asset_id ASC NULLS LAST)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_owner_log_owner
    ON public.atomicassets_asset_owner_log USING btree
    (owner ASC NULLS LAST)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_owner_log_current
    ON public.atomicassets_asset_owner_log USING btree
    (current)
    TABLESPACE pg_default;	

CREATE INDEX IF NOT EXISTS idx_atomicassets_asset_owner_log_asset_id_current_burned
    ON public.atomicassets_asset_owner_log USING btree
    (asset_id,current,burned)
    TABLESPACE pg_default;						

COMMENT ON TABLE public.atomicassets_asset_owner_log IS 'Store log of owner changes';

CREATE OR REPLACE FUNCTION update_current_flag_f()
RETURNS TRIGGER AS $$
DECLARE
    log_table_name TEXT;
    p_id_value TEXT;
		p_id_2_value TEXT;
BEGIN
    -- Set the table and column names based on the NEW row
    log_table_name := TG_TABLE_NAME;	

  -- Extract the id value from the NEW row using the dynamically specified id column name
    EXECUTE 'SELECT ($1).' || TG_ARGV[0] || ' FROM ' || log_table_name INTO p_id_value USING NEW;

		IF TG_ARGV[1] IS NOT NULL THEN
        EXECUTE 'SELECT ($1).' || TG_ARGV[1] || '::text FROM ' || log_table_name INTO p_id_2_value USING NEW;
    END IF;

    -- Update the specified log table setting the current column to false for the given _id
    -- Update the specified log table setting the current column to false for the given _id
    IF TG_ARGV[1] IS NOT NULL THEN
        EXECUTE 'UPDATE ' || log_table_name || ' SET current = false WHERE (' || TG_ARGV[0] || ')::text = $1 AND (' || TG_ARGV[1] || ')::text = $2'
        USING p_id_value, p_id_2_value;
    ELSE
        EXECUTE 'UPDATE ' || log_table_name || ' SET current = false WHERE (' || TG_ARGV[0] || ')::text = $1'
        USING p_id_value;
    END IF;

    NEW.current:=true;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER atomicassets_collection_account_log_update_current_flag_tr
BEFORE INSERT ON public.atomicassets_collection_account_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('collection_id');

CREATE TRIGGER atomicassets_collection_royalty_log_update_current_flag_tr
BEFORE INSERT ON public.atomicassets_collection_royalty_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('collection_id');

CREATE TRIGGER atomicassets_collection_data_log_update_current_flag_tr
BEFORE INSERT ON public.atomicassets_collection_data_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('collection_id');

CREATE TRIGGER atomicassets_asset_owner_log_set_current_tr
BEFORE INSERT ON public.atomicassets_asset_owner_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('asset_id');

CREATE TRIGGER atomicassets_format_log_set_current_tr
BEFORE INSERT ON public.atomicassets_schema_format_log
FOR EACH ROW EXECUTE FUNCTION update_current_flag_f('schema_id','collection_id');
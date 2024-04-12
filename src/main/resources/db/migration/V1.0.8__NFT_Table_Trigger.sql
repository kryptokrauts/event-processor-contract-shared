	---------------------------------------------------------------
	-- Trigger for transfer
	---------------------------------------------------------------

	CREATE OR REPLACE FUNCTION soonmarket_nft_tables_transfer_f()
	RETURNS TRIGGER AS $$
	DECLARE
			_card_asset_id bigint;
		_card_template_id bigint;
		_card_edition_size bigint;	
		_listing_id_rec RECORD;
		_deleted_listings RECORD;
		_deleted_listing_assets RECORD;
	BEGIN  
			RAISE WARNING '[% - transfer_id %] Started execution of trigger', TG_NAME, NEW.id;

		-- get all assets from the transfer, check if they are part of a now invalid listing and clear the tables in that case   
			FOR _listing_id_rec IN 
			SELECT DISTINCT sale_id as listing_id FROM 
			(
				SELECT 
					t3.sale_id,
					-- listing gets invalid when new owner (=receiver) is not the seller t
					BOOL_AND(COALESCE(t2.seller = t1.receiver,FALSE)) AS VALID
				FROM atomicassets_transfer t1
				INNER JOIN atomicassets_transfer_asset t5 ON t5.transfer_id=NEW.id
				INNER JOIN atomicmarket_sale_asset t3 ON t3.asset_id=t5.asset_id and t5.transfer_id=NEW.id	
				INNER JOIN atomicmarket_sale t2 ON t2.sale_id = t3.sale_id						
				WHERE NOT EXISTS(SELECT 1 from atomicmarket_sale_state t2 WHERE t3.sale_id=t2.sale_id)	
				AND t1.transfer_id=NEW.id
				GROUP by t3.sale_id	
			)
			WHERE NOT VALID
			LOOP
					RAISE WARNING '[% - transfer_id %] listing with id % got invalid through transfer, cleaning nft tables', TG_NAME, NEW.id, _listing_id_rec.listing_id;
					PERFORM soonmarket_nft_tables_clear_f(null, _listing_id_rec.listing_id);
					-- update listing / unlisted cards for given template_id
					RAISE WARNING '[% - transfer_id %] updating cards', TG_NAME, NEW.id;
					PERFORM 
						soonmarket_tables_update_listed_card_f(template_id),
						soonmarket_tables_update_unlisted_card_f(template_id)
					FROM(
						SELECT DISTINCT template_id
						FROM soonmarket_listing_v WHERE listing_id=_listing_id_rec.listing_id)t;
			END LOOP;

		
		-- in case listing gets valid again	
		-- remove listing assets and listings first
		FOR _listing_id_rec IN
		(
			SELECT DISTINCT listing_id
			FROM soonmarket_listing_valid_v 
			WHERE asset_id IN (SELECT asset_id FROM atomicassets_transfer_asset WHERE transfer_id = NEW.id)
		)
		LOOP

			-- Backup and delete the rows from atomicmarket_sale
			CREATE TEMP TABLE temp_deleted_listings AS
			    SELECT * FROM atomicmarket_sale
			    WHERE sale_id = _listing_id_rec.listing_id;			
			
			DELETE FROM atomicmarket_sale WHERE sale_id = _listing_id_rec.listing_id;
			RAISE WARNING '[% - transfer_id %] deleted atomicmarket_sale(s) entries for listing %', TG_NAME, NEW.id, _listing_id_rec.listing_id;		

			-- Backup and delete the rows from atomicmarket_sale_asset
			CREATE TEMP TABLE temp_deleted_listing_assets AS
			    SELECT * FROM atomicmarket_sale_asset
			    WHERE sale_id = _listing_id_rec.listing_id;
			
			-- Delete the rows from atomicmarket_sale_asset
			DELETE FROM atomicmarket_sale_asset	WHERE sale_id = _listing_id_rec.listing_id;
			RAISE WARNING '[% - transfer_id %] deleted atomicmarket_sale_asset(s) entries for listing %', TG_NAME, NEW.id, _listing_id_rec.listing_id;
			
			-- for add listing "simulate" a new listing by inserting the old dataset again
			
			IF (SELECT COUNT(*) FROM temp_deleted_listings) > 0 THEN
				RAISE WARNING '[% - transfer_id %] % invalid listings got valid again', TG_NAME, NEW.id, _listing_id_rec.listing_id;
				DELETE FROM t_soonmarket_nft_card_log WHERE type='sale' AND id=_listing_id_rec.listing_id AND processed=true;
				INSERT INTO atomicmarket_sale SELECT * FROM temp_deleted_listings;		
				INSERT INTO atomicmarket_sale_asset SELECT * FROM temp_deleted_listing_assets;				
			END IF;

			DROP TABLE temp_deleted_listings;
			DROP TABLE temp_deleted_listing_assets;
		
		END LOOP;

		-- TODO: do the same for buyoffers
				
		RAISE WARNING '[% - transfer_id %] Execution of trigger took % ms', TG_NAME, NEW.id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

		-- update soonmarket_nft_card_log to mark transfer as processed
		UPDATE t_soonmarket_nft_card_log SET processed = TRUE	WHERE type = 'transfer' and id = NEW.id and processed = false;

		RETURN NEW;

	END;
	$$ LANGUAGE plpgsql;

-- card log insert helper function
CREATE OR REPLACE FUNCTION public.soonmarket_transfer_notify_data_available_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
	BEGIN 
		IF TG_TABLE_NAME = 'atomicassets_transfer' THEN 
			-- completion count = 1(base entry) + # of bundle_size entries (if bundle, 1 for the primary asset otherwise) + number of owner_log changes for every bundle asset
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.transfer_id, 'transfer', 1 + COALESCE(2*NEW.bundle_size,2));
		ELSE
			IF NEW.transfer_id IS NOT NULL THEN
				PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.transfer_id, 'transfer', null);
			END IF;
		END IF;
		RETURN NEW;
	END;
$BODY$;

-- trigger to fill notify log for transfers

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_transfer_tr
AFTER INSERT ON public.atomicassets_transfer
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_transfer_notify_data_available_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_transfer_asset_tr
AFTER INSERT ON public.atomicassets_transfer_asset
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_transfer_notify_data_available_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_transfer_owner_tr
AFTER INSERT ON public.atomicassets_asset_owner_log
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_transfer_notify_data_available_f();

-- trigger transfer creation after insert count is equal to completion count

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_transfer_created_tr
AFTER INSERT OR UPDATE ON public.t_soonmarket_nft_card_log
FOR EACH ROW 
WHEN (NEW.type='transfer' AND NEW.completion_count = NEW.insert_count AND NEW.processed = false)
EXECUTE FUNCTION soonmarket_nft_tables_transfer_f();
---------------------------------------
-- Trigger for incoming auction bid
---------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_bid_f()
RETURNS TRIGGER AS $$
BEGIN  

	RAISE WARNING '[% - auction_id %] Started Execution of trigger', TG_NAME, NEW.auction_id;
	-- soonmarket_nft table
	UPDATE soonmarket_nft SET 
		blocknum = NEW.blocknum,
		block_timestamp = NEW.block_timestamp,
		auction_current_bid = NEW.current_bid,
		num_bids = NEW.bid_number
	WHERE auction_id = NEW.auction_id;

	RAISE WARNING '[% - auction_id %] updated soonmarket_nft table', TG_NAME, NEW.auction_id;
	
	-- soonmarket_nft_card table
	UPDATE soonmarket_nft_card SET 
		blocknum = NEW.blocknum,
		block_timestamp = NEW.block_timestamp,
		auction_current_bid = NEW.current_bid,
		highest_bidder = NEW.bidder,
		num_bids = NEW.bid_number
	WHERE auction_id = NEW.auction_id;

	RAISE WARNING '[% - auction_id %] updated soonmarket_card table', TG_NAME, NEW.auction_id;
	
	-- update end dates if set
	IF NEW.updated_end_time IS NOT NULL THEN
	   UPDATE soonmarket_nft SET auction_end_date = NEW.updated_end_time WHERE auction_id = NEW.auction_id;
	   UPDATE soonmarket_nft_card SET auction_end_date = NEW.updated_end_time WHERE auction_id = NEW.auction_id;
	END IF;

	RAISE WARNING '[% - auction_id %] Execution of trigger took % ms', TG_NAME, NEW.auction_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_bid_tr
AFTER INSERT ON public.atomicmarket_auction_bid_log
FOR EACH ROW EXECUTE FUNCTION soonmarket_nft_tables_auction_bid_f();	

---------------------------------------------------------------
-- Trigger for auction cancelled or ended without bids
---------------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_cancel_or_end_no_bid_f()
RETURNS TRIGGER AS $$
DECLARE
  _card_asset_id bigint;
	_card_template_id bigint;
	_card_edition_size bigint;
BEGIN  
	RAISE WARNING '[% - auction_id %] Started Execution of trigger', TG_NAME, NEW.auction_id;
	
	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(NEW.auction_id, null);
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.auction_id
	GROUP BY template_id;
		
	RAISE WARNING '[% - auction_id %] Execution of trigger took % ms', TG_NAME, NEW.auction_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_cancel_or_end_no_bid_tr
AFTER INSERT ON public.atomicmarket_auction_state
FOR EACH ROW 
WHEN (NEW.state=2 or NEW.state=4)
EXECUTE FUNCTION soonmarket_nft_tables_auction_cancel_or_end_no_bid_f();

---------------------------------------------------------
-- Trigger for incoming auction ended with bids
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_ended_with_bid_f()
RETURNS TRIGGER AS $$
DECLARE
  _card_asset_id bigint;
	_card_template_id bigint;
	_card_edition_size bigint;
BEGIN  
	RAISE WARNING '[% - auction_id %] Started Execution of trigger', TG_NAME, NEW.auction_id;

	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(NEW.auction_id, null);

	RAISE WARNING '[% - auction_id %] Updating lastSoldFor after successful auction',TG_NAME, NEW.auction_id;
	PERFORM soonmarket_nft_tables_update_last_sold_for_f(asset_id, template_id, edition_size)
	FROM soonmarket_asset_base_v
	WHERE asset_id in (SELECT asset_id from atomicmarket_auction_asset WHERE auction_id = NEW.auction_id);					

	RAISE WARNING '[% - auction_id %] Updating card state after successful auction',TG_NAME, NEW.auction_id;
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.auction_id
	GROUP BY template_id;

	RAISE WARNING '[% - auction_id %] Execution of trigger took % ms', TG_NAME, NEW.auction_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_ended_with_bid_tr
AFTER INSERT ON public.atomicmarket_auction_state
FOR EACH ROW 
WHEN (NEW.state=3)
EXECUTE FUNCTION soonmarket_nft_tables_auction_ended_with_bid_f();

---------------------------------------------------------
-- Trigger for auction created
-- insert/updated auctions in soonmarket_nft and soonmarket_nft_card
-- update num_auctions/listings/bundles for editions
-- update unlisted cards
---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.soonmarket_nft_tables_auction_started_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE	
	_edition_size int;
	_id bigint;
	_serial int;
	_template_id bigint;
	_min_edition_serial int;
	_min_edition_asset_id bigint;
	-- auction params
	_blocknum bigint;
	_block_timestamp bigint;
	_auction_end_date bigint; 
	_auction_token text;
	_auction_starting_bid DOUBLE PRECISION;
	_auction_royalty DOUBLE PRECISION;
	_auction_seller text;
	_primary_asset_id bigint;
	_bundle boolean;
	_bundle_size int;	
BEGIN
	RAISE WARNING '[% - auction_id %] Started Execution of trigger', TG_NAME, NEW.id;

	SELECT 
		blocknum, block_timestamp, end_time, token, price, collection_fee, bundle, bundle_size, seller, primary_asset_id
	INTO 
		_blocknum, _block_timestamp, _auction_end_date, _auction_token, _auction_starting_bid, _auction_royalty, _bundle, _bundle_size, _auction_seller, _primary_asset_id
	FROM atomicmarket_auction
	WHERE auction_id = NEW.id;

-- soonmarket_nft: update auction data for all assets within auction (in case of bundle auction)
	
	UPDATE soonmarket_nft
	SET (blocknum, block_timestamp, auction_id, auction_end_date, auction_token, auction_starting_bid, auction_royalty, auction_seller, bundle, bundle_size) =
		(_blocknum, _block_timestamp, NEW.id, _auction_end_date, _auction_token, _auction_starting_bid, _auction_royalty, _auction_seller, _bundle, _bundle_size)
	WHERE asset_id in (SELECT asset_id from atomicmarket_auction_asset where auction_id = NEW.id);
	RAISE WARNING '[% - auction_id %] Updated soonmarket_nft table entries (bundle = %), primary asset_id: %', TG_NAME, NEW.id, _bundle, _primary_asset_id;
-- soonmarket_nft_card table
	
	-- get edition size
	SELECT edition_size, template_id, serial 
	INTO _edition_size, _template_id, _serial 
	FROM soonmarket_asset_base_v 
	WHERE asset_id = _primary_asset_id;
	
	-- if 1:1 single auction update card
	IF _edition_size = 1 AND NOT _bundle THEN
		RAISE WARNING '[% - auction_id %] is not a bundle and 1of1 - updating soonmarket_nft_card for asset_id %', TG_NAME, NEW.id, _primary_asset_id;
		UPDATE soonmarket_nft_card		
	 	SET (blocknum, block_timestamp, auction_id, auction_seller, auction_end_date, auction_token, auction_starting_bid, auction_royalty, bundle, bundle_size) =
			(_blocknum, _block_timestamp, NEW.id, _auction_seller, _auction_end_date, _auction_token, _auction_starting_bid, _auction_royalty, _bundle, _bundle_size),
			 _card_quick_action = 'quick_bid',
			 _card_state = 'single'
		WHERE asset_id = _primary_asset_id;
	
	-- if 1:N (edition)
	ELSE		
		-- create a new auction/auction bundle card by duplicating the existing 
		RAISE WARNING '[% - auction_id %] is edition, creating new auction card from template_id %',TG_NAME, NEW.id, _template_id;
		SELECT * INTO _id FROM copy_row_f(_template_id,'soonmarket_nft_card');
		
		-- updating card to primary NFT values and auction
		UPDATE soonmarket_nft_card 
		SET (blocknum, block_timestamp, auction_id, auction_seller, auction_end_date, auction_token, auction_starting_bid, auction_royalty, bundle, bundle_size) =
			(_blocknum, _block_timestamp, NEW.id, _auction_seller, _auction_end_date, _auction_token, _auction_starting_bid, _auction_royalty, _bundle, _bundle_size),
			 serial = _serial,
			 asset_id = _primary_asset_id,
			 _card_quick_action = CASE WHEN _bundle THEN 'no_action' ELSE 'quick_bid' END,
			 _card_state = CASE WHEN _bundle THEN 'bundle' ELSE 'single' END,
			 display = true
		WHERE id = _id;
		RAISE WARNING '[% - auction_id %] is edition,updated soonmarket_nft_card with id %',TG_NAME, NEW.id, _id;
	END IF;	
	
	-- update num_bundles for all editions included in bundle (can be multiple template_ids)
	IF _bundle THEN
		RAISE WARNING '[% - auction_id %] is bundle, setting num_bundles infos for template_id % in soonmarket_nft_card',TG_NAME, NEW.id, _template_id; 
		UPDATE soonmarket_nft_card SET num_bundles = COALESCE(num_bundles,0)+1 
		WHERE edition_size !=1 AND template_id in (SELECT template_id from atomicmarket_auction_asset WHERE auction_id = NEW.id);
	END IF;
	-- update num_auctions for all NFTs of this edition
	IF NOT _bundle AND _edition_size != 1 THEN
		RAISE WARNING '[% - auction_id %] is bundle, setting num_auctions for template_id % in soonmarket_nft_card',TG_NAME, NEW.id, _template_id; 
		UPDATE soonmarket_nft_card SET num_auctions = COALESCE(num_auctions,0)+1
		WHERE template_id = _template_id;		
	END IF;	
	
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.id
	GROUP BY template_id;

	-- update t_soonmarket_nft_card_log
	UPDATE t_soonmarket_nft_card_log
	SET processed = TRUE
	WHERE type = 'auction' and id = NEW.id and processed = false;
	
	RAISE WARNING '[% - auction_id %] Execution of trigger took % ms', TG_NAME, NEW.id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$BODY$;

-- card log insert helper function
CREATE OR REPLACE FUNCTION public.soonmarket_auction_notify_data_available_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
	BEGIN 
		IF TG_TABLE_NAME = 'atomicmarket_auction' THEN 
			-- completion count = 1(base entry) + # of bundle_size entries (if bundle, 1 for the primary asset otherwise)
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.auction_id, 'auction', 1 + COALESCE(NEW.bundle_size,1));
		ELSE
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.auction_id, 'auction', null);
		END IF;
		RETURN NEW;
	END;
$BODY$;

-- trigger to fill notify log for auctions

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_started_tr
AFTER INSERT ON public.atomicmarket_auction
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_auction_notify_data_available_f();

CREATE OR REPLACE TRIGGER  soonmarket_nft_tables_assets_auction_started_tr
    AFTER INSERT
    ON public.atomicmarket_auction_asset
    FOR EACH ROW
EXECUTE FUNCTION soonmarket_auction_notify_data_available_f();

-- trigger auction creation after insert count is equal to completion count

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_started_tr
AFTER INSERT OR UPDATE ON public.t_soonmarket_nft_card_log
FOR EACH ROW 
WHEN (NEW.type='auction' AND NEW.completion_count = NEW.insert_count AND NEW.processed = false)
EXECUTE FUNCTION soonmarket_nft_tables_auction_started_f();

---------------------------------------------------------
-- Trigger for claim NFT by buyer
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_claim_by_buyer_f()
RETURNS TRIGGER AS $$
BEGIN  

	RAISE WARNING '[% - auction_id %] Started Execution of trigger', TG_NAME, NEW.auction_id;
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.auction_id
	GROUP BY template_id;
		
	RAISE WARNING '[% - auction_id %] Execution of trigger took % ms', TG_NAME, NEW.auction_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_auction_claim_by_buyer_tr
AFTER INSERT ON public.atomicmarket_auction_claim_log
FOR EACH ROW 
WHEN (NEW.claimed_by_buyer is not null AND NEW.current)
EXECUTE FUNCTION soonmarket_nft_tables_auction_claim_by_buyer_f();

---------------------------------------------------------
-- Trigger for burn NFT
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_burn_f()
RETURNS TRIGGER AS $$
DECLARE
	_edition_size int;
	_template_id bigint;
BEGIN 	
	RAISE WARNING '[% - asset_id %] Started Execution of trigger', TG_NAME, NEW.asset_id;
-- soonmarket_nft: update burned flag	
	UPDATE soonmarket_nft
	SET burned = true, burned_by = NEW.owner, burned_date = NEW.block_timestamp
	WHERE asset_id = NEW.asset_id;
	
	SELECT edition_size, template_id 
	INTO _edition_size, _template_id 
	FROM soonmarket_asset_base_v WHERE asset_id = NEW.asset_id;

	-- check if asset was part of bundle listings, if yes remove since listings are invalid now
	RAISE WARNING '[% - asset_id %] checking if bundle listings got invalid after burn', TG_NAME, NEW.asset_id;
	EXECUTE soonmarket_tables_remove_invalid_bundle_listings_f(NEW.asset_id);
		
	-- if 1:1 delete card
	IF _edition_size = 1 THEN
		RAISE WARNING '[% - asset_id %] asset was 1of1, deleting card', TG_NAME, NEW.asset_id;
		DELETE FROM soonmarket_nft_card WHERE asset_id = NEW.asset_id and edition_size = 1;
	-- 1:N (edition)
	ELSE		
		-- check if all assets of edition are burned now, if yes delete card
		IF (SELECT COUNT(*) FROM soonmarket_asset_base_v WHERE template_id = _template_id AND NOT burned) = 0 THEN
			RAISE WARNING '[% - asset_id %] asset was edition and last unburned of edition, deleting card', TG_NAME, NEW.asset_id;
			DELETE FROM soonmarket_nft_card WHERE asset_id = NEW.asset_id;
		END IF;
			RAISE WARNING '[% - asset_id %] asset was edition but not last unburned of edition, updating card', TG_NAME, NEW.asset_id;
		-- check if asset was listed: update potential floor listing since listing is now invalid
		EXECUTE soonmarket_tables_update_listed_card_f(_template_id);
		-- check if asset was unlisted and burned asset was last unlisted 
		EXECUTE soonmarket_tables_update_unlisted_card_f(_template_id);
	END IF;
		
	RAISE WARNING '[% - asset_id %] Execution of trigger took % ms', TG_NAME, NEW.asset_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_burn_tr
AFTER INSERT ON public.atomicassets_asset_owner_log
FOR EACH ROW 
WHEN (NEW.current AND NEW.burned)
EXECUTE FUNCTION soonmarket_nft_tables_burn_f();

---------------------------------------------------------
-- Trigger for updating the asset owner
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_owner_f()
RETURNS TRIGGER AS $$
BEGIN 	

	RAISE WARNING '[% - asset_id %] Started Execution of trigger', TG_NAME, NEW.asset_id;

-- soonmarket_nft: update owner
	UPDATE soonmarket_nft
	SET owner = NEW.owner
	WHERE asset_id = NEW.asset_id;
	RAISE WARNING '[% - asset_id %] updated owner in soonmarket_nft', TG_NAME, NEW.asset_id;
	
-- soonmarket_nft_card: update owner
	UPDATE soonmarket_nft_card
	SET owner = NEW.owner
	WHERE asset_id = NEW.asset_id;
	RAISE WARNING '[% - asset_id %] updated owner in soonmarket_nft_card', TG_NAME, NEW.asset_id;
		
	RAISE WARNING '[% - asset_id %] Execution of trigger took % ms', TG_NAME, NEW.asset_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_owner_tr
AFTER INSERT ON public.atomicassets_asset_owner_log
FOR EACH ROW 
WHEN (NEW.current AND NOT NEW.burned)
EXECUTE FUNCTION soonmarket_nft_tables_update_owner_f();

---------------------------------------------------------
-- Trigger for mint NFT
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_mint_f()
RETURNS TRIGGER AS $$
DECLARE
	_edition_size int;
	_serial int;
	_template_id bigint;
	_asset_id bigint;
BEGIN
	RAISE WARNING '[% - asset_id/template_id % type %] Started Execution of trigger', TG_NAME, NEW.id, NEW.type;

	-- if minting asset = 1of1 or edition NFT with serial > 1 the reference id is the asset_id
	IF NEW.type in ('mint_asset','mint_template') THEN
		SELECT edition_size,serial,template_id, asset_id INTO _edition_size,_serial,_template_id,_asset_id 
		FROM soonmarket_asset_base_v WHERE asset_id = NEW.id;
	ELSE 
	-- otherwise it is the first NFT of the template
		SELECT max(edition_size),max(serial),max(template_id), max(asset_id) INTO _edition_size,_serial,_template_id,_asset_id 
		FROM soonmarket_asset_base_v WHERE template_id = NEW.id;
	END IF;

	RAISE WARNING '[% - asset_id %] inserting new entry into soonmarket_nft', TG_NAME, _asset_id;
-- soonmarket_nft: create new entry if not blacklisted
	INSERT INTO soonmarket_nft
	(blocknum, block_timestamp, asset_id, template_id, schema_id, collection_id, 
	 serial, edition_size, transferable, burnable, owner, mint_date, received_date, 
	 asset_name, asset_media, asset_media_type, asset_media_preview, 
	 collection_name, collection_image, royalty, creator, has_kyc, shielded, burned)	
	 SELECT
	 t1.blocknum, t1.block_timestamp, asset_id, template_id, schema_id, collection_id, 
	 serial, edition_size, transferable, burnable, t1.receiver, t1.block_timestamp, received_date, 
	 asset_name, asset_media, asset_media_type, asset_media_preview, 
	 collection_name, collection_image, royalty, creator, t2.has_kyc, shielded, false
	 FROM soonmarket_asset_v t1
	 LEFT JOIN soonmarket_profile t2 ON t1.creator=t2.account
	 WHERE asset_id = _asset_id;	
		 
		-- serial = 1 means no card exists -> create a new card
	IF _serial = 1 THEN
	RAISE WARNING '[% - asset_id %] asset has serial 1, inserting new entry into soonmarket_nft_card', TG_NAME, _asset_id;
	INSERT INTO soonmarket_nft_card
	(blocknum, block_timestamp, asset_id, template_id, schema_id, collection_id, 
		serial, edition_size, transferable, burnable, owner, mint_date, 
		asset_name, asset_media, asset_media_type, asset_media_preview, 
		collection_name, collection_image, royalty, creator, has_kyc, shielded,
		_card_state, _card_quick_action, display, blacklisted)	
		SELECT
		t1.blocknum, t1.block_timestamp, asset_id, template_id, schema_id, collection_id, 
		serial, edition_size, transferable, burnable, t1.receiver, t1.block_timestamp, 
		asset_name, asset_media, asset_media_type, asset_media_preview, 
		collection_name, collection_image, royalty, creator, t2.has_kyc, shielded,
		CASE WHEN _edition_size != 1 THEN 'edition' ELSE 'single' END,
		'quick_offer', true, false
		FROM soonmarket_asset_v t1
		LEFT JOIN soonmarket_profile t2 ON t1.creator=t2.account
		WHERE asset_id = _asset_id AND NOT blacklisted;
	END IF;
	-- serial > 1 means means a new NFT of an existing edition is minted - check if unlisted card display needs to be updated
	IF _serial > 1 AND _template_id IS NOT null THEN			
		RAISE WARNING '[% - asset_id %] asset has serial > 1, updating card entry in soonmarket_nft_card', TG_NAME, _asset_id;
		EXECUTE soonmarket_tables_update_unlisted_card_f(_template_id);
	END IF;

-- update soonmarket_nft_card_log to mark transfer as processed
	UPDATE t_soonmarket_nft_card_log SET processed = TRUE	WHERE type = NEW.type and id = NEW.id and processed = false;

	RAISE WARNING '[% - asset_id %] Execution of trigger took % ms', TG_NAME, _asset_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
	
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- card log insert helper function
CREATE OR REPLACE FUNCTION public.soonmarket_mint_notify_data_available_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
	DECLARE		 
		_completion_count_edition int;
		_mint_type text;
		_ref_id bigint;
	BEGIN 
	-- completion count = 1(base entry) + either template or asset_data (when 1of1 without template)
		IF TG_TABLE_NAME = 'atomicassets_asset' THEN 									
			-- template check if it is the first mint - if yes we need template and asset entry otherwise we just need the asset entry
			-- this needs to be distinguished because the reference id is in the second case then the asset_id rather than the template_id
			IF NEW.template_id IS NOT NULL THEN				
				SELECT 				
				CASE WHEN serial=1 THEN 2 ELSE 1 END,
				CASE WHEN serial=1 THEN 'mint_template_first_serial' ELSE 'mint_template' END,
				CASE WHEN serial=1 THEN NEW.template_id ELSE NEW.asset_id END
				INTO 
				_completion_count_edition, _mint_type, _ref_id
			FROM atomicassets_asset WHERE asset_id=NEW.asset_id;
				PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, _ref_id, _mint_type, _completion_count_edition);
			ELSE
				PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.asset_id, 'mint_asset', 2);
			END IF;
		ELSE
			IF TG_TABLE_NAME = 'atomicassets_template' THEN
				PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.template_id, 'mint_template_first_serial', null);
			ELSE
				PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.asset_id, 'mint_asset', null);
			END IF;
		END IF;
		RETURN NEW;
	END;
$BODY$;

-- actual trigger - we only need it for the first asset

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_mint_tr
AFTER INSERT ON public.atomicassets_asset
FOR EACH ROW
EXECUTE FUNCTION soonmarket_mint_notify_data_available_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_asset_data_mint_tr
AFTER INSERT ON public.atomicassets_asset_data
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_mint_notify_data_available_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_template_mint_tr
AFTER INSERT ON public.atomicassets_template
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_mint_notify_data_available_f();

-- trigger transfer creation after insert count is equal to completion count

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_mint_created_tr
AFTER INSERT OR UPDATE ON public.t_soonmarket_nft_card_log
FOR EACH ROW 
WHEN (NEW.type in('mint_template','mint_template_first_serial','mint_asset') AND NEW.completion_count = NEW.insert_count AND NEW.processed = false)
EXECUTE FUNCTION soonmarket_nft_tables_mint_f();

---------------------------------------------------------
-- Trigger for (bundle) listing created
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_listing_created_f()
RETURNS TRIGGER AS $$
DECLARE	
	_edition_size int;
	_id bigint;
	_serial int;
	_template_id bigint;
	-- listing params
	_blocknum bigint;
	_block_timestamp bigint;
	_listing_date bigint; 
	_listing_token text;
	_listing_price DOUBLE PRECISION;
	_listing_royalty DOUBLE PRECISION;
	_listing_seller text;
	_primary_asset_id bigint;
	_bundle boolean;
	_bundle_size int;
BEGIN 	
-- soonmarket_nft: update listing data for all assets within listing (in case of bundle listing)
	RAISE WARNING '[% - listing_id %] Execution of trigger started at %', TG_NAME, NEW.id, clock_timestamp();

	SELECT 
		blocknum, block_timestamp, primary_asset_id, block_timestamp, token, price, collection_fee, bundle, bundle_size, seller
	INTO 
		_blocknum, _block_timestamp, _primary_asset_id, _listing_date, _listing_token, _listing_price, _listing_royalty, _bundle, _bundle_size, _listing_seller
	FROM atomicmarket_sale
	WHERE sale_id = NEW.id;

	-- if bundle listing, add additional NFT entry
	IF _bundle THEN
		RAISE WARNING '[% - listing_id %] New Listing is bundle, adding entry to soonmarket_nft', TG_NAME, NEW.id;
		SELECT * INTO _id FROM copy_row_f((SELECT template_id FROM soonmarket_asset_base_v WHERE asset_id = _primary_asset_id),'soonmarket_nft');

		UPDATE soonmarket_nft
		SET (blocknum, block_timestamp, asset_id, listing_id, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
			(_blocknum, _block_timestamp, _primary_asset_id, NEW.id, _listing_date, _listing_token, _listing_price, _listing_royalty, _bundle, _bundle_size)
		WHERE id = _id;
	
	ELSE
		RAISE WARNING '[% - listing_id %] New Listing is not a bundle, updating entry in soonmarket_nft', TG_NAME, NEW.id;
		-- otherwise just update
		UPDATE soonmarket_nft
		SET (blocknum, block_timestamp, listing_id, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
			(_blocknum, _block_timestamp, NEW.id, _listing_date, _listing_token, _listing_price, _listing_royalty, _bundle, _bundle_size)
		WHERE asset_id in (SELECT asset_id from atomicmarket_sale_asset where sale_id = NEW.id);
	END IF;		

-- soonmarket_nft_card table
	
	-- get edition size
	SELECT edition_size, template_id, serial 
	INTO _edition_size, _template_id, _serial 
	FROM soonmarket_asset_base_v 
	WHERE asset_id = _primary_asset_id;
	
	-- if single listing, update card
	IF _bundle IS false THEN
		-- if 1:1 update listing info
		IF _edition_size = 1 THEN
			RAISE WARNING '[% - listing_id %] New listing is not a bundle and 1of1, updating card in soonmarket_nft_card for asset_id %', TG_NAME, NEW.id,_primary_asset_id;
			UPDATE soonmarket_nft_card		
			SET (blocknum, block_timestamp, listing_id, listing_seller, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
				(_blocknum, _block_timestamp, NEW.id, _listing_seller, _listing_date, _listing_token, _listing_price, _listing_royalty, _bundle, _bundle_size),
				 _card_quick_action = 'quick_buy',
				 _card_state = 'single' 
			WHERE asset_id = _primary_asset_id;
		
		-- if edition check, update floor price and num_listings
		ELSE	
			RAISE WARNING '[% - listing_id %] New listing is not a bundle and edition, updating card in soonmarket_nft_card for template_id %', TG_NAME, NEW.id,_template_id;
			EXECUTE soonmarket_tables_update_listed_card_f(_template_id);
		END IF;
	
	-- otherwise its a bundle listing
	ELSE
		-- create a new bundle card by duplicating the existing 
		RAISE WARNING '[% - listing_id %] Listing is bundle, adding new entry to soonmarket_nft_card and updating num_bundles', TG_NAME, NEW.id;
		SELECT * INTO _id FROM copy_row_f(_template_id,'soonmarket_nft_card');
		
		-- updating card to primary NFT values and listing
		UPDATE soonmarket_nft_card 
		SET (blocknum, block_timestamp, listing_id, listing_seller, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
			(_blocknum, _block_timestamp, NEW.id, _listing_seller, _listing_date, _listing_token, _listing_price, _listing_royalty, _bundle, _bundle_size),
			 serial = _serial,
			 asset_id = _primary_asset_id,
			 _card_quick_action ='no_action',
			 _card_state = 'bundle',
			 display = true
		WHERE id = _id;
		
		-- update num_bundles for all editions included in bundle (can be multiple template_ids)	
		UPDATE soonmarket_nft_card SET num_bundles = COALESCE(num_bundles,0)+1 
		WHERE edition_size !=1 AND template_id in (SELECT template_id from atomicmarket_sale_asset WHERE sale_id = NEW.id);

	END IF;		

	-- update t_soonmarket_nft_card_log
	UPDATE t_soonmarket_nft_card_log
	SET processed = TRUE
	WHERE type = 'sale' and id = NEW.id and processed = false;
	
	RAISE WARNING '[% - listing_id %] Execution of trigger took % ms', TG_NAME, NEW.id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- card log insert helper function
CREATE OR REPLACE FUNCTION public.soonmarket_sale_notify_data_available_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
	BEGIN 
		IF TG_TABLE_NAME = 'atomicmarket_sale' THEN 
			-- completion count = 1(base entry) + # of bundle_size entries (if bundle, 1 for the primary asset otherwise)
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.sale_id, 'sale', 1 + COALESCE(NEW.bundle_size,1));
		ELSE
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.sale_id, 'sale', null);
		END IF;
		RETURN NEW;
	END;
$BODY$;

-- trigger to fill notify log for listings

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_listing_created_tr
AFTER INSERT ON public.atomicmarket_sale
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_sale_notify_data_available_f();

CREATE OR REPLACE TRIGGER  soonmarket_nft_tables_assets_listing_started_tr
    AFTER INSERT
    ON public.atomicmarket_sale_asset
    FOR EACH ROW
EXECUTE FUNCTION public.soonmarket_sale_notify_data_available_f();

-- trigger listing creation after insert count is equal to completion count

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_listing_started_tr
AFTER INSERT OR UPDATE ON public.t_soonmarket_nft_card_log
FOR EACH ROW 
WHEN (NEW.type='sale' AND NEW.completion_count = NEW.insert_count AND NEW.processed=false)
EXECUTE FUNCTION soonmarket_nft_tables_listing_created_f();

---------------------------------------------------------------
-- Trigger for listing update (cancel or purchase)
---------------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_listing_update_f()
RETURNS TRIGGER AS $$
DECLARE
  _card_asset_id bigint;
	_card_template_id bigint;
	_card_edition_size bigint;
BEGIN  

	RAISE WARNING '[% - listing_id %] execution of trigger started at %', TG_NAME, NEW.sale_id, clock_timestamp();

	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(null, NEW.sale_id);
	-- check if asset was listed: update potential floor listing since listing is now invalid
	EXECUTE soonmarket_tables_update_listed_card_f(_card_template_id);
	-- check if asset was unlisted and burned asset was last unlisted 
	EXECUTE soonmarket_tables_update_unlisted_card_f(_card_template_id);
	
	-- if sold, update last sold for
	IF NEW.state = 3 THEN	
		RAISE WARNING '[% - listing_id %] has state sold, updating last sold for', TG_NAME, NEW.sale_id;
		PERFORM soonmarket_nft_tables_update_last_sold_for_f(asset_id, template_id, edition_size)
		FROM soonmarket_asset_base_v
		WHERE asset_id in (SELECT asset_id from atomicmarket_sale_asset WHERE sale_id = NEW.sale_id);
	END IF;
		
	RAISE WARNING '[% - listing_id %] Execution of trigger took % ms', TG_NAME, NEW.sale_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_listing_update_tr
AFTER INSERT ON public.atomicmarket_sale_state
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_listing_update_f();

---------------------------------------------------------
-- Trigger for buyoffer created
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_buyoffer_created_f()
RETURNS TRIGGER AS $$
BEGIN 	

	RAISE WARNING '[% - buyoffer_id %] Execution of trigger started at %', TG_NAME, NEW.id, clock_timestamp();

-- soonmarket_nft: set has_offers
	
	RAISE WARNING '[% - buyoffer_id %] setting has_offers in soonmarket_nft',TG_NAME, NEW.id;
	UPDATE soonmarket_nft
	SET has_offers = true
	WHERE asset_id in (SELECT asset_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.id);
	
-- soonmarket_nft_card table
	
	-- update 1:1
	RAISE WARNING '[% - buyoffer_id %] setting has_offers in soonmarket_nft_card',TG_NAME, NEW.id;
	UPDATE soonmarket_nft_card
	SET has_offers = true
	WHERE asset_id in (SELECT asset_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.id);
	
	-- update edition
	UPDATE soonmarket_nft_card
	SET has_offers = true
	WHERE template_id in (SELECT template_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.id);
		
	-- update soonmarket_nft_card_log
	UPDATE t_soonmarket_nft_card_log
	SET processed = TRUE
	WHERE type = 'buyoffer' and id = NEW.id and processed = false;
	
	RAISE WARNING '[% - buyoffer_id %] Execution of trigger took % ms', TG_NAME, NEW.id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- card log insert helper function
CREATE OR REPLACE FUNCTION public.soonmarket_buyoffer_notify_data_available_f()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
	BEGIN 
		IF TG_TABLE_NAME = 'atomicmarket_buyoffer' THEN 
			-- completion count = 1(base entry) + # of bundle_size entries (if bundle, 1 for the primary asset otherwise)
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.buyoffer_id, 'buyoffer', 1 + COALESCE(NEW.bundle_size,1));
		ELSE
			PERFORM soonmarket_nft_card_log_update_f(NEW.blocknum, NEW.block_timestamp, NEW.buyoffer_id, 'buyoffer', null);
		END IF;
		RETURN NEW;
	END;
$BODY$;

-- trigger to fill notify log for buyoffers

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_buyoffer_created_tr
AFTER INSERT ON public.atomicmarket_buyoffer
FOR EACH ROW 
EXECUTE FUNCTION public.soonmarket_buyoffer_notify_data_available_f();		

CREATE OR REPLACE TRIGGER  soonmarket_nft_tables_asset_buyoffer_started_tr
    AFTER INSERT
    ON public.atomicmarket_buyoffer_asset
    FOR EACH ROW
EXECUTE FUNCTION public.soonmarket_buyoffer_notify_data_available_f();

-- trigger buyoffer creation after insert count is equal to completion count

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_buyoffer_created_tr
AFTER INSERT OR UPDATE ON public.t_soonmarket_nft_card_log
FOR EACH ROW 
WHEN (NEW.type='buyoffer' AND NEW.completion_count = NEW.insert_count AND NEW.processed = false)
EXECUTE FUNCTION soonmarket_nft_tables_buyoffer_created_f();

---------------------------------------------------------
-- Trigger for buyoffers
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_buyoffer_f()
RETURNS TRIGGER AS $$
DECLARE
	_card_asset_id bigint;
	_card_template_id bigint;
	_card_edition_size int;
BEGIN 	

	RAISE WARNING '[% - buyoffer_id %] Execution of trigger started at %', TG_NAME, NEW.buyoffer_id, clock_timestamp();

	RAISE WARNING '[% - buyoffer_id %] update has_offers in table soonmarket_nft', TG_NAME, NEW.buyoffer_id;
-- soonmarket_nft: set has_offers	
	WITH buyoffers AS (
    	SELECT t1.asset_id, 
        COALESCE(COUNT(t2.*), 0) AS cnt
		FROM atomicmarket_buyoffer_asset t1
		LEFT JOIN soonmarket_buyoffer_open_v t2 ON t2.asset_id = t1.asset_id
		WHERE t1.buyoffer_id = NEW.buyoffer_id
		GROUP BY t1.asset_id
	)
	UPDATE soonmarket_nft AS n
	SET has_offers = CASE WHEN bo.cnt > 0 THEN TRUE ELSE FALSE END
	FROM buyoffers AS bo
	WHERE n.asset_id = bo.asset_id OR bo.asset_id IS NULL;
	
-- soonmarket_nft_card table
	
	RAISE WARNING '[% - buyoffer_id %] update has_offers in table soonmarket_nft_card', TG_NAME, NEW.buyoffer_id;
	-- update 1:1
	WITH buyoffers AS (
    	SELECT t1.asset_id, 
        COALESCE(COUNT(t2.*), 0) AS cnt
		FROM atomicmarket_buyoffer_asset t1
		LEFT JOIN soonmarket_buyoffer_open_v t2 ON t2.asset_id = t1.asset_id
		WHERE t1.buyoffer_id = NEW.buyoffer_id
		GROUP BY t1.asset_id
	)
	UPDATE soonmarket_nft_card AS n
	SET has_offers = CASE WHEN bo.cnt > 0 THEN TRUE ELSE FALSE END
	FROM buyoffers AS bo
	WHERE n.asset_id = bo.asset_id OR bo.asset_id IS NULL;
	
	-- update edition
	WITH buyoffers AS (
    	SELECT t1.template_id, 
        COALESCE(COUNT(t2.*), 0) AS cnt
		FROM atomicmarket_buyoffer_asset t1
		LEFT JOIN soonmarket_buyoffer_open_v t2 ON t2.template_id = t1.template_id
		WHERE t1.buyoffer_id = NEW.buyoffer_id
		GROUP BY t1.template_id
	)
	UPDATE soonmarket_nft_card AS n
	SET has_offers = CASE WHEN bo.cnt > 0 THEN TRUE ELSE FALSE END
	FROM buyoffers AS bo
	WHERE n.template_id = bo.template_id OR bo.template_id IS NULL;
	
	-- if offer accepted update last sold for	
	IF TG_TABLE_NAME = 'atomicmarket_buyoffer_state' THEN
		IF NEW.state = 3 THEN		
			RAISE WARNING '[% - buyoffer_id %] Updating lastSoldFor after successful buyoffer',TG_NAME, NEW.buyoffer_id;
			PERFORM soonmarket_nft_tables_update_last_sold_for_f(asset_id, template_id, edition_size)
			FROM soonmarket_asset_base_v
			WHERE asset_id in (SELECT asset_id from atomicmarket_buyoffer_asset WHERE buyoffer_id = NEW.buyoffer_id);					
		END IF;
	END IF;
		
	RAISE WARNING '[% - buyoffer_id %] Execution of trigger took % ms', TG_NAME, NEW.buyoffer_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
		
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_buyoffer_state_tr
AFTER INSERT ON public.atomicmarket_buyoffer_state
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_buyoffer_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_buyoffer_tr
AFTER INSERT ON public.atomicmarket_buyoffer
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_buyoffer_f();

---------------------------------------------------------
-- Trigger to update shielding / deshielding
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_shielded_f()
RETURNS TRIGGER AS $$

BEGIN 
	RAISE WARNING '[% - collection_id %] Execution of trigger started at %', TG_NAME, NEW.collection_id, clock_timestamp();

-- soonmarket_nft: update shielded flag for all NFTs
	RAISE WARNING '[% - collection_id %] Setting shielded to %',TG_NAME, NEW.collection_id,
	(CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END, 
	CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END);
	
	UPDATE soonmarket_nft
	SET shielded = CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END
	WHERE collection_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
	
-- soonmarket_nft_card: table update shielded flag for all NFTs
	
	UPDATE soonmarket_nft_card
	SET shielded = CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END
	WHERE collection_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
	
	IF TG_OP = 'DELETE' THEN 
		RETURN null;
	ELSE
		RETURN NEW;
	END IF;

	RAISE WARNING '[% - collection_id %] Execution of trigger took % ms', TG_NAME, NEW.collection_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_shielded_tr
AFTER INSERT OR DELETE ON public.nft_watch_shielding
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_shielded_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_shielded_tr
AFTER INSERT OR DELETE ON public.soonmarket_internal_shielding
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_shielded_f();

---------------------------------------------------------
-- Trigger to update kyc
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_kyc_f()
RETURNS TRIGGER AS $$

BEGIN 	
-- soonmarket_nft: update has_kyc flag for all NFTs
	RAISE WARNING '[% - profile %] Setting KYC for profile to value %',TG_NAME, NEW.account, NEW.has_kyc;
	
	UPDATE soonmarket_nft SET has_kyc = NEW.has_kyc WHERE creator = NEW.account;
	
-- soonmarket_nft_card: update has_kyc flag for all NFTs
	
	UPDATE soonmarket_nft_card SET has_kyc = NEW.has_kyc WHERE creator = NEW.account;

	RAISE WARNING '[% - profile %] Execution of trigger took % ms', TG_NAME, NEW.account, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger for new profiles
CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_kyc_insert_tr
AFTER INSERT ON public.soonmarket_profile
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_kyc_f();

-- trigger on update
CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_kyc_update_tr
AFTER UPDATE ON public.soonmarket_profile
FOR EACH ROW 
WHEN (OLD.has_kyc IS DISTINCT FROM NEW.has_kyc)
EXECUTE FUNCTION soonmarket_nft_tables_update_kyc_f();

---------------------------------------------------------
-- Trigger for blacklisting a collection
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_blacklist_f()
RETURNS TRIGGER AS $$

BEGIN 	
	RAISE WARNING '[% - collection_id %] Execution of trigger started at %', TG_NAME, NEW.collection_id, clock_timestamp();

	RAISE WARNING '[% - collection_id %] Setting blacklist to %',TG_NAME, NEW.collection_id,
	(CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END, 
	CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END);
-- soonmarket_nft: update all asset with given collection_id	
	UPDATE soonmarket_nft
	SET blacklisted = CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END
	WHERE collection_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
	
-- soonmarket_nft_card: table update shielded flag for all NFTs
	
	UPDATE soonmarket_nft_card
	SET blacklisted = CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END
	WHERE collection_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
	
	IF TG_OP = 'DELETE' THEN 
		RETURN null;
	ELSE
		RETURN NEW;
	END IF;
	RAISE WARNING '[% - collection_id %] Execution of trigger took % ms', TG_NAME, NEW.collection_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_blacklist_tr
AFTER INSERT OR DELETE ON public.nft_watch_blacklist
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_blacklist_f();

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_blacklist_tr
AFTER INSERT OR DELETE ON public.soonmarket_internal_blacklist
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_blacklist_f();

---------------------------------------------------------
-- Trigger to update collection data
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_collection_data_f()
RETURNS TRIGGER AS $$

BEGIN 	
	IF NEW.current THEN
-- soonmarket_nft: update collection data for all entries
	
		RAISE WARNING '[% - collection_id %] Execution of trigger started at %', TG_NAME, NEW.collection_id, clock_timestamp();

		UPDATE soonmarket_nft SET 
			collection_name = NEW.name,
			collection_image = NEW.image
		WHERE collection_id = NEW.collection_id;

-- soonmarket_nft_card: update collection data for all entries

		UPDATE soonmarket_nft_card SET 
			collection_name = NEW.name,
			collection_image = NEW.image
		WHERE collection_id = NEW.collection_id;

		RAISE WARNING '[% - collection_id %] Execution of trigger took % ms', TG_NAME, NEW.collection_id, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
	
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER soonmarket_nft_tables_update_collection_data_tr
AFTER INSERT ON public.atomicassets_collection_data_log
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_collection_data_f();
	
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

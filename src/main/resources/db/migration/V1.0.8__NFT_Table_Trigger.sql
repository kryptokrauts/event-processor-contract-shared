	
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

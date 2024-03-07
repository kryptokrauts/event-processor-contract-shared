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
BEGIN  
	-- get all assets from the transfer, check if they are part of a now invalid listing and clear the tables in that case   
    FOR _listing_id_rec IN 
		SELECT DISTINCT listing_id FROM soonmarket_listing_v 
        WHERE asset_id IN (SELECT asset_id FROM atomicassets_transfer_asset WHERE transfer_id = NEW.transfer_id)
        AND state IS NULL AND NOT VALID
    LOOP
        PERFORM soonmarket_nft_tables_clear_f(null, _listing_id_rec.listing_id);
    END LOOP;

    RETURN NEW;
	
	-- update listing / unlisted cards for given template_id
	WITH transfer_assets AS
	(
		SELECT asset_id FROM atomicassets_transfer_asset WHERE transfer_id=NEW.transfer_id
	)
	SELECT 
		soonmarket_tables_update_listed_card_f(template_id),
		soonmarket_tables_update_unlisted_card_f(template_id)
	FROM(
		SELECT DISTINCT template_id AS template_id
	 	FROM soonmarket_listing_v 
		WHERE asset_id IN (SELECT asset_id FROM transfer_assets) AND state is null AND NOT VALID
	)t;
	
-- in case listing gets valid again
	-- get valid listings
	WITH valid_listings AS (
    	SELECT DISTINCT listing_id 
    	FROM soonmarket_listing_valid_v 
    	WHERE asset_id IN (SELECT asset_id FROM atomicassets_transfer_asset WHERE transfer_id = NEW.transfer_id)
	)
	-- for every valid listing that is not in soonmarket_nft, add listing by "simulating" a new listing
	UPDATE atomicmarket_sale
	SET sale_id = sale_id
	FROM valid_listings t1
	LEFT JOIN soonmarket_nft t2 ON t1.listing_id = t2.listing_id
	WHERE atomicmarket_sale.sale_id = t1.listing_id AND t2.listing_id IS NULL;
			
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_transfer_tr
AFTER INSERT ON public.atomicassets_transfer
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_transfer_f();

---------------------------------------
-- Trigger for incoming auction bid
---------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_bid_f()
RETURNS TRIGGER AS $$
BEGIN  
	-- soonmarket_nft table
	UPDATE soonmarket_nft SET 
		auction_current_bid = NEW.current_bid,
		num_bids = NEW.bid_number
	WHERE auction_id = NEW.auction_id;
	
	-- soonmarket_nft_card table
	UPDATE soonmarket_nft_card SET 
		auction_current_bid = NEW.current_bid,
		highest_bidder = NEW.bidder,
		num_bids = NEW.bid_number
	WHERE auction_id = NEW.auction_id;
	
	-- update end dates if set
	IF NEW.updated_end_time IS NOT NULL THEN
	   UPDATE soonmarket_nft SET auction_end_date = NEW.updated_end_time WHERE auction_id = NEW.auction_id;
	   UPDATE soonmarket_nft_card SET auction_end_date = NEW.updated_end_time WHERE auction_id = NEW.auction_id;
	END IF;

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_auction_bid_tr
AFTER INSERT ON public.atomicmarket_event_auction_bid_log
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
	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(NEW.auction_id, null);
	-- update unlisted card state
	EXECUTE soonmarket_tables_update_unlisted_card_f(_card_template_id);
		
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_auction_cancel_or_end_no_bid_tr
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
	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(NEW.auction_id, null);
	EXECUTE soonmarket_nft_tables_update_last_sold_for_f(_card_asset_id, _card_template_id, _card_edition_size);
	-- update unlisted card state
	EXECUTE soonmarket_tables_update_unlisted_card_f(_card_template_id);

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_auction_ended_with_bid_tr
AFTER INSERT ON public.atomicmarket_auction_state
FOR EACH ROW 
WHEN (NEW.state=3)
EXECUTE FUNCTION soonmarket_nft_tables_auction_ended_with_bid_f();

---------------------------------------------------------
-- Trigger for newly created auction
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_started_f()
RETURNS TRIGGER AS $$
DECLARE	
	_edition_size int;
	_id bigint;
	_serial int;
	_template_id bigint;
	_min_edition_serial int;
	_min_edition_asset_id bigint;
BEGIN 	
-- soonmarket_nft: update auction data for all assets within auction (in case of bundle auction)
	
	UPDATE soonmarket_nft
	SET (auction_id, auction_end_date, auction_token, auction_starting_bid, auction_royalty, bundle, bundle_size) =
		(NEW.auction_id, NEW.end_time, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size)
	WHERE asset_id in (SELECT asset_id from atomicmarket_auction_asset where auction_id = NEW.auction_id);
	
-- soonmarket_nft_card table
	
	-- get edition size
	SELECT edition_size, template_id, serial 
	INTO _edition_size, _template_id, _serial 
	FROM soonmarket_asset_base_v 
	WHERE asset_id = NEW.primary_asset_id;
	
	-- if 1:1 update card
	IF _edition_size = 1 THEN
		UPDATE soonmarket_nft_card		
	 	SET (auction_id, auction_seller, auction_end_date, auction_token, auction_starting_bid, auction_royalty, bundle, bundle_size) =
			(NEW.auction_id, NEW.seller, NEW.end_time, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size),
			 _card_quick_action = CASE WHEN NEW.bundle THEN 'no_action' ELSE 'quick_bid' END,
			 _card_state = CASE WHEN NEW.bundle THEN 'bundle' ELSE 'single' END
		WHERE asset_id = NEW.primary_asset_id;
	
	-- if 1:N (edition)
	ELSE
		-- create a new auction/auction bundle card by duplicating the existing 
		SELECT * INTO _id FROM copy_row_f(_template_id,'soonmarket_nft_card');
		
		-- updating card to primary NFT values and auction
		UPDATE soonmarket_nft_card 
		SET (auction_id, auction_seller, auction_end_date, auction_token, auction_starting_bid, auction_royalty, bundle, bundle_size) =
			(NEW.auction_id, NEW.seller, NEW.end_time, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size),
			 serial = _serial,
			 asset_id = NEW.primary_asset_id,
			 _card_quick_action = CASE WHEN NEW.bundle THEN 'no_action' ELSE 'quick_bid' END,
			 _card_state = CASE WHEN NEW.bundle THEN 'bundle' ELSE 'single' END
		WHERE id = _id;
	END IF;	
	
	-- update num_bundles for all editions included in bundle (can be multiple template_ids)
	IF NEW.bundle THEN 
		UPDATE soonmarket_nft_card SET num_bundles = COALESCE(num_bundles,0)+1 
		WHERE edition_size !=1 AND template_id in (SELECT template_id from atomicmarket_auction_asset WHERE auction_id = NEW.auction_id);
	END IF;
	-- update num_auctions for all NFTs of this edition
	IF NOT NEW.bundle AND _edition_size != 1 THEN
		UPDATE soonmarket_nft_card SET num_auctions = COALESCE(num_auctions,0)+1
		WHERE template_id = _template_id;		
	END IF;	
	
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.auction_id
	GROUP BY template_id;
	
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_auction_started_tr
AFTER INSERT ON public.atomicmarket_auction
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_auction_started_f();

---------------------------------------------------------
-- Trigger for claim NFT by buyer
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_auction_claim_by_buyer_f()
RETURNS TRIGGER AS $$
BEGIN  
	-- update potential unlisted card state for all templates (if auction was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_auction_asset 
	WHERE auction_id = NEW.auction_id
	GROUP BY template_id;
		
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_auction_claim_by_buyer_tr
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
-- soonmarket_nft: update burned flag	
	UPDATE soonmarket_nft
	SET burned = true, burned_by = NEW.owner, burned_date = NEW.block_timestamp
	WHERE asset_id = NEW.asset_id;
	
-- soonmarket_nft_card: table update shielded flag for all NFTs
	SELECT edition_size, template_id 
	INTO _edition_size, _template_id 
	FROM soonmarket_asset_base_v WHERE asset_id = NEW.asset_id;

	-- check if asset was part of bundle listings, if yes remove since listings are invalid now
	EXECUTE soonmarket_tables_remove_invalid_bundle_listings_f(NEW.asset_id);
		
	-- if 1:1 delete card
	IF _edition_size = 1 THEN
		DELETE FROM soonmarket_nft_card WHERE asset_id = NEW.asset_id and edition_size = 1;
	-- 1:N (edition)
	ELSE
		-- check if all assets of edition are burned now, if yes delete card
		IF (SELECT COUNT(*) FROM soonmarket_asset_base_v WHERE template_id = _template_id AND NOT burned) = 0 THEN
			DELETE FROM soonmarket_nft_card WHERE asset_id = NEW.asset_id and edition_size = 1;
		END IF;
		-- check if asset was listed: update potential floor listing since listing is now invalid
		EXECUTE soonmarket_tables_update_listed_card_f(_template_id);
		-- check if asset was unlisted and burned asset was last unlisted 
		EXECUTE soonmarket_tables_update_unlisted_card_f(_template_id);
	END IF;
		
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_burn_tr
AFTER INSERT ON public.atomicassets_asset_owner_log
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_burn_f();

---------------------------------------------------------
-- Trigger for mint NFT
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_mint_f()
RETURNS TRIGGER AS $$
DECLARE
	_edition_size int;
BEGIN 	
-- soonmarket_nft: create new entry if not blacklisted
	INSERT INTO soonmarket_nft
	(blocknum, block_timestamp, asset_id, template_id, schema_id, collection_id, 
	 serial, edition_size, transferable, burnable, owner, mint_date, received_date, 
	 asset_name, asset_media, asset_media_type, asset_media_preview, 
	 collection_name, collection_image, royalty, creator, has_kyc, shielded)	
	 SELECT
	 t1.blocknum, t1.block_timestamp, asset_id, template_id, schema_id, collection_id, 
	 serial, edition_size, transferable, burnable, OWNER, t1.block_timestamp, received_date, 
	 asset_name, asset_media, asset_media_type, asset_media_preview, 
	 collection_name, collection_image, royalty, creator, t2.has_kyc, shielded
	 FROM soonmarket_asset_v t1
	 LEFT JOIN soonmarket_profile t2 ON t1.creator=t2.account
	 WHERE asset_id = NEW.asset_id AND NOT blacklisted;
	
	SELECT edition_size INTO _edition_size FROM soonmarket_asset_base_v WHERE asset_id = NEW.asset_id;
		
	CASE 
		-- serial = 1 means no card exists -> create a new card
		WHEN NEW.serial = 1 THEN
			INSERT INTO soonmarket_nft_card
			(blocknum, block_timestamp, asset_id, template_id, schema_id, collection_id, 
			 serial, edition_size, transferable, burnable, owner, mint_date, 
			 asset_name, asset_media, asset_media_type, asset_media_preview, 
			 collection_name, collection_image, royalty, creator, has_kyc, shielded,
			 _card_state, _card_quick_action, display, blacklisted)	
			 SELECT
			 t1.blocknum, t1.block_timestamp, asset_id, template_id, schema_id, collection_id, 
			 serial, edition_size, transferable, burnable, OWNER, t1.block_timestamp, 
			 asset_name, asset_media, asset_media_type, asset_media_preview, 
			 collection_name, collection_image, royalty, creator, t2.has_kyc, shielded,
			 CASE WHEN _edition_size != 1 THEN 'edition' ELSE 'single' END,
			 'quick_offer', true, false
			 FROM soonmarket_asset_v t1
			 LEFT JOIN soonmarket_profile t2 ON t1.creator=t2.account
			 WHERE asset_id = NEW.asset_id AND NOT blacklisted;
		-- serial > 1 means means a new NFT of an existing edition is minted - check if unlisted card display needs to be updated
		WHEN NEW.serial > 1 AND NEW.template_id IS NOT null THEN			
			EXECUTE soonmarket_tables_update_unlisted_card_f(NEW.template_id);
	END CASE;

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
	
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_mint_tr
AFTER INSERT ON public.atomicassets_asset
FOR EACH ROW 
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
BEGIN 	
-- soonmarket_nft: update auction data for all assets within listing (in case of bundle listing)
	
	UPDATE soonmarket_nft
	SET (listing_id, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
		(NEW.sale_id, NEW.block_timestamp, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size)
	WHERE asset_id in (SELECT asset_id from atomicmarket_sale_asset where sale_id = NEW.sale_id);
	
-- soonmarket_nft_card table
	
	-- get edition size
	SELECT edition_size, template_id, serial 
	INTO _edition_size, _template_id, _serial 
	FROM soonmarket_asset_base_v 
	WHERE asset_id = NEW.primary_asset_id;
	
	-- if single listing, update card
	IF NEW.bundle IS NOT true THEN
		-- if 1:1 update listing info
		IF _edition_size = 1 THEN
			UPDATE soonmarket_nft_card		
			SET (listing_id, listing_seller, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
				(NEW.sale_id, NEW.seller, NEW.block_timestamp, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size),
				 _card_quick_action = CASE WHEN NEW.bundle THEN 'no_action' ELSE 'quick_buy' END,
				 _card_state = CASE WHEN NEW.bundle THEN 'bundle' ELSE 'single' END
			WHERE asset_id = NEW.primary_asset_id;
		
		-- if multiedition check, update floor price and num_listings
		ELSE			
			EXECUTE soonmarket_tables_update_listed_card_f(_template_id);
		END IF;
	
	-- otherwise its a bundle listing
	ELSE
		-- create a new bundle card by duplicating the existing 
		SELECT * INTO _id FROM copy_row_f(_template_id,'soonmarket_nft_card');
		
		-- updating card to primary NFT values and listing
		UPDATE soonmarket_nft_card 
		SET (listing_id, listing_seller, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
			(NEW.sale_id, NEW.seller, NEW.block_timestamp, NEW.token, NEW.price, NEW.collection_fee, NEW.bundle, NEW.bundle_size),
			 serial = _serial,
			 asset_id = NEW.primary_asset_id,
			 _card_quick_action ='no_action',
			 _card_state = 'bundle'
		WHERE id = _id;
		
		-- update num_bundles for all editions included in bundle (can be multiple template_ids)	
		UPDATE soonmarket_nft_card SET num_bundles = COALESCE(num_bundles,0)+1 
		WHERE edition_size !=1 AND template_id in (SELECT template_id from atomicmarket_sale_asset WHERE sale_id = NEW.sale_id);
		
	END IF;		
	
	-- update potential unlisted card state for all templates (if listing was bundle can be multiple)
	PERFORM soonmarket_tables_update_unlisted_card_f(template_id)
	FROM atomicmarket_sale_asset 
	WHERE sale_id = NEW.sale_id
	GROUP BY template_id;
	
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_listing_created_tr
AFTER INSERT ON public.atomicmarket_sale
FOR EACH ROW 
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
	SELECT * INTO _card_asset_id, _card_template_id, _card_edition_size FROM soonmarket_nft_tables_clear_f(null, NEW.sale_id);
	-- check if asset was listed: update potential floor listing since listing is now invalid
	EXECUTE soonmarket_tables_update_listed_card_f(_card_template_id);
	-- check if asset was unlisted and burned asset was last unlisted 
	EXECUTE soonmarket_tables_update_unlisted_card_f(_card_template_id);
	
	-- if sold, update last sold for
	IF NEW.state = 3 THEN
		EXECUTE soonmarket_nft_tables_update_last_sold_for_f(_card_asset_id, _card_template_id, _card_edition_size);
	END IF;
		
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_listing_update_tr
AFTER INSERT ON public.atomicmarket_sale_state
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_listing_update_f();

---------------------------------------------------------
-- Trigger for buyoffer created
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_buyoffer_created_f()
RETURNS TRIGGER AS $$
BEGIN 	
-- soonmarket_nft: set has_offers
	
	UPDATE soonmarket_nft
	SET has_offers = true
	WHERE asset_id in (SELECT asset_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.buyoffer_id);
	
-- soonmarket_nft_card table
	
	-- update 1:1
	UPDATE soonmarket_nft_card
	SET has_offers = true
	WHERE asset_id in (SELECT asset_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.buyoffer_id);
	
	-- update edition
	UPDATE soonmarket_nft_card
	SET has_offers = true
	WHERE template_id in (SELECT template_id from atomicmarket_buyoffer_asset where buyoffer_id = NEW.buyoffer_id);
		
	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_buyoffer_created_tr
AFTER INSERT ON public.atomicmarket_buyoffer
FOR EACH ROW 
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
			SELECT asset_id, template_id, edition_size 
			INTO _card_asset_id, _card_template_id, _card_edition_size 
			FROM soonmarket_asset_base_v
			WHERE asset_id = (SELECT primary_asset_id from atomicmarket_buyoffer WHERE buyoffer_id = NEW.buyoffer_id);		
			EXECUTE soonmarket_nft_tables_update_last_sold_for_f(_card_asset_id, _card_template_id, _card_edition_size);
		END IF;
	END IF;
		
	RAISE WARNING '% took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);
		
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_buyoffer_state_tr
AFTER INSERT ON public.atomicmarket_buyoffer_state
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_buyoffer_f();

CREATE TRIGGER soonmarket_nft_tables_buyoffer_tr
AFTER INSERT ON public.atomicmarket_buyoffer
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_buyoffer_f();

---------------------------------------------------------
-- Trigger to update shielding / deshielding
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_shielded_f()
RETURNS TRIGGER AS $$

BEGIN 	
-- soonmarket_nft: update shielded flag for all NFTs
	RAISE WARNING 'Setting shielded to % for collection %',
	CASE WHEN TG_OP = 'DELETE' THEN false ELSE true END, 
	CASE WHEN TG_OP = 'DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
	
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

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_update_shielded_tr
AFTER INSERT OR DELETE ON public.nft_watch_shielding
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_shielded_f();

CREATE TRIGGER soonmarket_nft_tables_update_shielded_tr
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
	RAISE WARNING 'Setting KYC for profile % to value %', NEW.account, NEW.has_kyc;
	
	UPDATE soonmarket_nft SET has_kyc = NEW.has_kyc WHERE creator = NEW.account;
	
-- soonmarket_nft_card: update has_kyc flag for all NFTs
	
	UPDATE soonmarket_nft_card SET has_kyc = NEW.has_kyc WHERE creator = NEW.account;

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_update_kyc_tr
AFTER INSERT OR UPDATE ON public.soonmarket_profile
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_update_kyc_f();

---------------------------------------------------------
-- Trigger for blacklisting a collection
---------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_blacklist_f()
RETURNS TRIGGER AS $$

BEGIN 	
	RAISE WARNING 'Blacklisting collection %', NEW.collection_id;
-- soonmarket_nft: remove all asset with given collection_id
	
	DELETE FROM soonmarket_nft WHERE collection_id = NEW.collection_id;
	
-- soonmarket_nft_card: table update shielded flag for all NFTs
	
	DELETE FROM soonmarket_nft_card WHERE collection_id = NEW.collection_id;

	RAISE WARNING 'Execution of trigger % took % ms', TG_NAME, (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

	RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soonmarket_nft_tables_blacklist_tr
AFTER INSERT ON public.nft_watch_blacklist
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_blacklist_f();

CREATE TRIGGER soonmarket_nft_tables_blacklist_tr
AFTER INSERT ON public.soonmarket_internal_blacklist
FOR EACH ROW 
EXECUTE FUNCTION soonmarket_nft_tables_blacklist_f();
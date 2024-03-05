---------------------------------------------------------------------------------
-- Function to clear market info from tables
-- Clear single auction/listing from soonmarket_nft and soonmarket_nft_card
-- Remove auction/bundle cards
-- update num_auctions/listings/bundles for editions
---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION soonmarket_nft_tables_clear_f
(_auction_id bigint, _listing_id bigint, OUT _card_asset_id bigint, OUT _card_template_id bigint, OUT _card_edition_size bigint)
LANGUAGE plpgsql 
AS $$
DECLARE
	_card_bundle bool;	
	_num_auctions int;
	_num_listings int;	
	_num_bundles int;
	_dynamic_where text;
BEGIN  

-- construct where clause depending on parameters
	CASE
		WHEN _auction_id IS NOT NULL THEN
		_dynamic_where := 'auction_id = ' || _auction_id;
		WHEN _listing_id IS NOT NULL THEN
		_dynamic_where := 'listing_id = ' || _listing_id;
	END CASE;
	
	EXECUTE format('
	SELECT bundle, asset_id, template_id, edition_size    
	FROM soonmarket_nft_card
	WHERE ' || _dynamic_where) INTO _card_bundle, _card_asset_id, _card_template_id, _card_edition_size;
	
-- soonmarket_nft: clear auction and listing reference
	EXECUTE '
	UPDATE soonmarket_nft SET 
		auction_id = null,
		auction_token = null,		
		auction_starting_bid = null,		
		auction_current_bid = null,
		auction_end_date = null,
		auction_royalty = null,
		listing_id = null,
		listing_token = null,
		listing_price = null,
		listing_date = null,
		listing_royalty = null,
		bundle = false,
		bundle_size = null,
		num_bids = null,
		filter_token = null
		WHERE ' || _dynamic_where;
	
-- soonmarket_nft_card table
	-- bundle case
	IF _card_bundle THEN
		EXECUTE 'DELETE FROM soonmarket_nft_card' || _dynamic_where;
		
		-- update num_bundles for all assets in bundle auction / listing
		IF _card_bundle AND _auction_id is not null THEN 
			UPDATE soonmarket_nft_card 
			SET num_bundles = CASE WHEN num_bundles > 1 THEN num_bundles -1 ELSE NULL END 
			WHERE template_id in (SELECT template_id from soonmarket_auction_bundle_assets_v WHERE auction_id = _auction_id);
		END IF;
		IF _card_bundle AND _listing_id is not null THEN 
			UPDATE soonmarket_nft_card 
			SET num_bundles = CASE WHEN num_bundles > 1 THEN num_bundles -1 ELSE NULL END 
			WHERE template_id in (SELECT template_id from soonmarket_listing_bundle_assets_v WHERE listing_id = _listing_id);
		END IF;
	END IF;
	-- edition case
	IF _card_edition_size != 1 THEN
		-- delete auction/bundle auction/bundle listing card because there is always an single listed/unlisted card
		IF _auction_id IS NOT null THEN
			DELETE FROM soonmarket_nft_card WHERE auction_id = _auction_id;	
		END IF;

		IF NOT _card_bundle AND _auction_id is not null THEN 
			UPDATE soonmarket_nft_card 
			SET num_auctions = CASE WHEN num_auctions > 1 THEN num_auctions -1 ELSE NULL END 
			WHERE template_id=_card_template_id AND edition_size != 1;
		END IF;

		IF NOT _card_bundle AND _listing_id is not null THEN 
			UPDATE soonmarket_nft_card 
			SET num_listings = CASE WHEN num_listings > 1 THEN num_listings -1 ELSE NULL END 
			WHERE template_id=_card_template_id and edition_size != 1;
		END IF;
	-- 1:1 case
	ELSE
		EXECUTE '
		UPDATE soonmarket_nft_card SET 
		auction_id = null,
		auction_seller = null,
		auction_token = null,
		auction_royalty = null,
		auction_starting_bid = null,
		auction_current_bid = null,
		auction_end_date = null,
		auction_start_date = null,		
		highest_bidder = null,		
		listing_id = null,
		listing_token = null,
		listing_price = null,
		listing_date = null,
		listing_royalty = null,		
		bundle = false,
		bundle_size = null,
		bundle_index = null,
		num_bids = null,
		_card_state = ''single'',
		_card_quick_action = ''quick_offer''
		WHERE ' || _dynamic_where;
	END IF;	

	RAISE WARNING 'Execution of function % took % ms', 'soonmarket_nft_tables_update_last_sold_for_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$;

----------------------------------------------
-- Function to update last sold for
----------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_nft_tables_update_last_sold_for_f(_card_asset_id bigint, _card_template_id bigint, _card_edition_size bigint)
RETURNS void AS $$
DECLARE
	_dynamic_nft_card_query text;
BEGIN  
	-- soonmarket_nft: update lastSoldFor info for the given asset
	UPDATE soonmarket_nft
	 SET (price, token) =
		(SELECT t1.price, t1.token FROM soonmarket_last_sold_for_asset_v t1 WHERE t1.asset_id = _card_asset_id)
	WHERE asset_id = _card_asset_id;
		
	_dynamic_nft_card_query = 'UPDATE %I
	 SET (last_sold_for_price, last_sold_for_token, last_sold_for_price_usd, last_sold_for_royalty_usd, last_sold_for_market_fee_usd) =
		(SELECT 
		 t1.price, t1.token, t1.price*t2.usd, t1.royalty*t1.price*t2.usd , t1.price*(t1.maker_market_fee+t1.taker_market_fee)*t2.usd 
		 FROM %I t1
		 LEFT JOIN soonmarket_exchange_rate_latest_v t2 ON t1.token = t2.token_symbol
		 WHERE t1.%I = %L)
	WHERE %I = %L';	
	
	-- soonmarket_nft_card table: update either asset or template
	IF _card_edition_size != 1 THEN
		EXECUTE format(_dynamic_nft_card_query, 'soonmarket_nft_card', 'soonmarket_last_sold_for_template_v', 'template_id', _card_template_id,'template_id', _card_template_id);		
	ELSE
		EXECUTE format(_dynamic_nft_card_query, 'soonmarket_nft_card', 'soonmarket_last_sold_for_asset_v', 'asset_id', _card_asset_id, 'asset_id', _card_asset_id);
	END IF;

	RAISE WARNING 'Execution of function % took % ms', 'soonmarket_nft_tables_clear_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soonmarket_nft_tables_update_last_sold_for_f
    IS 'Update last sold for at asset or template level';

----------------------------------------------
-- Generic Function to copy existing dataset
----------------------------------------------

CREATE OR REPLACE FUNCTION copy_row_f(_template_id bigint, _table_name text)
RETURNS bigint AS $$
DECLARE
  _column_list TEXT;
	_id bigint;
BEGIN
    SELECT string_agg(column_name, ', ')
    INTO _column_list
    FROM information_schema.columns
    WHERE table_name = _table_name
    AND column_name NOT IN (
        SELECT a.attname 
        FROM pg_index i 
        JOIN pg_attribute a ON a.attrelid = i.indrelid 
        AND a.attnum = ANY(i.indkey) 
        WHERE i.indrelid = _table_name::regclass 
        AND i.indisprimary)
		AND column_name NOT like '%auction%'
		AND column_name NOT like '%listing%';
	
    EXECUTE format('
			INSERT INTO %I (%s)
			SELECT %s
			FROM %I
			WHERE template_id=%L
			LIMIT 1
			RETURNING id',
      _table_name, _column_list, _column_list, _table_name, _template_id) into _id;
		
	RETURN _id;

	RAISE WARNING 'Execution of function % took % ms', 'copy_row_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION copy_row_f
    IS 'Generic function to copy an existing dataset from soonmarket_nft_card / soonmarket_nft without the PK';

--------------------------------------------------------------------------------------------
-- Update unlisted card, remove display if all NFTs of edition are auctioned / bundle listed
--------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_tables_update_unlisted_card_f(_template_id bigint)
RETURNS void AS $$
DECLARE
	_min_edition_serial int;
	_min_edition_asset_id bigint;
BEGIN
-- query for lowest serial which is not auctioned or listed
	SELECT min(serial), min(asset_id) INTO _min_edition_serial, _min_edition_asset_id
	FROM soonmarket_asset_base_v 
	WHERE 
		edition_size != 1
		AND template_id = _template_id 
		AND NOT burned
		AND asset_id NOT IN (select asset_id FROM soonmarket_edition_listings_v WHERE template_id = _template_id)
		AND asset_id NOT IN (select asset_id FROM soonmarket_edition_auctions_v WHERE template_id = _template_id);

-- if there is a min_edition_serial, change serial of unlisted card to lowest available
	IF _min_edition_serial IS NOT NULL THEN
		UPDATE soonmarket_nft_card 
		SET 
			serial = _min_edition_serial, 
			asset_id = _min_edition_asset_id,
			_card_quick_action = 'quick_offer',
			-- set visible only when no listing exists, otherwise we have a listing card
			display = CASE WHEN (SELECT COUNT(*) FROM soonmarket_listing_valid_v WHERE template_id=_template_id AND NOT bundle) = 0 THEN true ELSE false END
		WHERE edition_size != 1 AND template_id = _template_id AND auction_id IS NULL AND listing_id IS NULL AND NOT bundle;
-- if none left, set display of unlisted card to false
	ELSE
		UPDATE soonmarket_nft_card SET display = false 
		WHERE edition_size != 1 AND template_id = _template_id AND auction_id IS NULL AND listing_id IS NULL AND NOT bundle AND display;
	END IF;
	
	RAISE WARNING 'Execution of function % took % ms', 'soonmarket_tables_update_unlisted_card_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soonmarket_tables_update_unlisted_card_f
    IS 'Update unlisted card with lowest serial or remove card from being displayed when no unlisted asset exists anymore';

------------------------------------------------------------------------------
-- Update listed card (serial, floor price) and num_listings for given edition
-- set card to unlisted if no listings exist
------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_tables_update_listed_card_f(_template_id bigint)
RETURNS void AS $$
DECLARE
	_min_edition_serial int;
	_min_edition_asset_id bigint;
	_num_listings int;
BEGIN
-- query for lowest priced single listing
		SELECT 
		min(serial), 
		min(asset_id), 
		(SELECT count(*) FROM soonmarket_listing_valid_v WHERE template_id = _template_id AND NOT bundle)
	INTO _min_edition_serial, _min_edition_asset_id, _num_listings
	FROM soonmarket_asset_base_v 
	WHERE 
		edition_size != 1
		AND template_id = _template_id 
		AND NOT burned
		AND asset_id = (select asset_id FROM soonmarket_listing_valid_v WHERE template_id = _template_id AND NOT bundle ORDER BY listing_price_usd asc LIMIT 1)
		AND asset_id NOT IN (select asset_id FROM soonmarket_edition_auctions_v WHERE template_id = _template_id);

-- if single listing exists
	IF _min_edition_serial IS NOT NULL THEN		
		UPDATE soonmarket_nft_card 
		SET 
			serial = _min_edition_serial, 
			asset_id = _min_edition_asset_id,
			display = true,
			_card_quick_action = 'quick_buy',
			num_listings = CASE WHEN _num_listings > 0 THEN _num_listings ELSE NULL END,
			-- set new floor
			(listing_id, listing_price, listing_token, listing_royalty, listing_date, listing_seller) =
			(SELECT 
			 	listing_id, listing_price, listing_token, listing_royalty, listing_date, seller
			 FROM soonmarket_listing_valid_v 
			 WHERE asset_id = _min_edition_asset_id AND NOT bundle)			
		WHERE edition_size != 1 AND template_id = _template_id AND auction_id IS NULL AND NOT bundle;
-- if no single listing exists anymore switch to unlisted and null the listing info
	ELSE
		UPDATE soonmarket_nft_card 
		SET 
			_card_quick_action = 'quick_offer',
			num_listings = null,
			(listing_id, listing_price, listing_token, listing_royalty, listing_date, listing_seller) =
			(null,null,null,null,null,null)
		WHERE edition_size != 1 AND template_id = _template_id AND auction_id IS NULL AND NOT bundle AND display;
	END IF;

	RAISE WARNING 'Execution of function % took % ms', 'soonmarket_tables_update_listed_card_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soonmarket_tables_update_listed_card_f
    IS 'Update listed card floor price and num_listings or transform to unlisted if no listing exists anymore';

----------------------------------------------
-- Remove invalid bundle cards
----------------------------------------------

CREATE OR REPLACE FUNCTION soonmarket_tables_remove_invalid_bundle_listings_f(_asset_id bigint)
RETURNS void AS $$
DECLARE
	_delete_count int;
BEGIN
-- soonmarket_nft
	-- clear all listings which have the asset_id
	UPDATE soonmarket_nft_card 
	SET (listing_id, listing_seller, listing_date, listing_token, listing_price, listing_royalty, bundle, bundle_size) =
			(null, null, null, null, null, null, false, null)
	WHERE listing_id IN
	(SELECT DISTINCT listing_id FROM soonmarket_listing_v WHERE bundle AND asset_id = _asset_id AND state is null AND NOT valid);

-- soonmarket_nft_card
	-- remove all bundle cards which have an open listing containing the given invalid asset_id
	WITH deleted as(
	DELETE FROM soonmarket_nft_card WHERE bundle AND listing_id in
	(SELECT DISTINCT listing_id FROM soonmarket_listing_v WHERE bundle AND asset_id = _asset_id AND state is null AND NOT valid)
	 RETURNING listing_id
	)
	-- get number of deleted cards
	SELECT count(*) FROM deleted into _delete_count;

	-- if bundles were delete, update num_bundles
	IF _delete_count > 0 THEN
		UPDATE soonmarket_nft_card 
		SET num_bundles = CASE WHEN num_bundles > _delete_count+1 THEN _delete_count ELSE NULL END 
		WHERE template_id in (SELECT template_id from soonmarket_listing_bundle_assets_v WHERE listing_id = _listing_id);
	END IF;

	RAISE WARNING 'Execution of function % took % ms', 'soonmarket_tables_remove_invalid_bundle_listings_f', (floor(EXTRACT(epoch FROM clock_timestamp())*1000) - floor(EXTRACT(epoch FROM now()))*1000);

END;

$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soonmarket_tables_remove_invalid_bundle_listings_f
    IS 'Clear all listings, update num_bundles and remove all bundle cards, which have an open listing containing the given invalid asset_id';
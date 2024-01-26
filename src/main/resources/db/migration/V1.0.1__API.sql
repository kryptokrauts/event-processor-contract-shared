----------------------------------
-- Collection Tables
----------------------------------	

CREATE OR REPLACE VIEW atomicassets_collection_detail_v as
SELECT 
col.*,
cdl.name,
crl.royalty,
cdl.description,
cdl.image,
cdl.data,
GREATEST(cdl.blocknum, crl.blocknum) AS update_blocknum
FROM atomicassets_collection col
LEFT JOIN LATERAL ( SELECT * from public.atomicassets_collection_data_log cdl WHERE col.collection_id = cdl.collection_id ORDER BY cdl.blocknum DESC LIMIT 1) cdl ON TRUE
LEFT JOIN LATERAL ( SELECT * from public.atomicassets_collection_royalty_log crl WHERE col.collection_id = crl.collection_id ORDER BY crl.blocknum DESC LIMIT 1) crl ON TRUE

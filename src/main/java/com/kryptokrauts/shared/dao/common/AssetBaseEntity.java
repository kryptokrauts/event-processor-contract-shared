package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._Asset;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_asset_base_v")
public class AssetBaseEntity extends PanacheEntityBase {

  @Id private Long assetId;

  private String assetName;

  private String assetMediaType;

  private String assetMedia;

  private String assetMediaPreview;

  private Long editionSize;

  private Long serial;

  private String owner;

  public static _Asset toModel(Long assetId) {
    AssetBaseEntity asset = AssetBaseEntity.find("assetId = ?1", assetId).firstResult();
    if (asset != null) {
      return _Asset.builder()
          .assetId(asset.getAssetId())
          .assetMedia(asset.getAssetMedia())
          .assetMediaPreview(asset.getAssetMediaPreview())
          .assetMediaType(asset.getAssetMediaType())
          .assetName(asset.getAssetName())
          .editionSize(asset.getEditionSize())
          .serial(asset.getSerial())
          .build();
    }
    return _Asset.builder().build();
  }
}

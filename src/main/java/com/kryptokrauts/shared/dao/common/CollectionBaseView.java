package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.model.common._Collection;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_collection_base_v")
public class CollectionBaseView extends PanacheEntityBase {

  @Id private String collectionId;

  private String collectionName;

  private String collectionImage;

  private String creator;

  private Boolean shielded;

  private Boolean blacklisted;

  private Double royalty;

  public _Collection toModel() {
    return _Collection.builder()
        .collectionId(collectionId)
        .collectionImage(collectionImage)
        .collectionName(collectionName)
        .shielded(shielded)
        .blacklisted(blacklisted)
        .creator(BaseMapper.mapAccount(creator))
        .royalty(royalty)
        .build();
  }

  public static _Collection toModel(String collectionId) {
    CollectionBaseView collection =
        CollectionBaseView.find("collectionId = ?1", collectionId).firstResult();
    if (collection != null) {
      return collection.toModel();
    }
    return _Collection.builder().build();
  }
}

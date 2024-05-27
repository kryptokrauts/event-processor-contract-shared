package com.kryptokrauts.shared.model.common;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import com.kryptokrauts.shared.model._BaseModel;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@JsonPropertyOrder(alphabetic = true)
@Getter
@Setter
@SuperBuilder
@RegisterForReflection
public class _Asset extends _BaseModel {

  private Long assetId;

  private Long templateId;

  private String assetName;

  private String assetMediaType;

  private String assetMedia;

  private String assetMediaPreview;

  private Long editionSize;

  private Long serial;

  private _Account owner;
}

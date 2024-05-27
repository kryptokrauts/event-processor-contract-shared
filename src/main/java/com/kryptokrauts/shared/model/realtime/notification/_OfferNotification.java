package com.kryptokrauts.shared.model.realtime.notification;

import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Notification;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@Getter
@Setter
@SuperBuilder
@RegisterForReflection
public class _OfferNotification extends _Notification {

  private Long buyofferId;

  private _PriceInfo price;

  private _Asset asset;

  private Integer bundleSize;

  private _Account seller;

  private _Account buyer;

  private String message;
}

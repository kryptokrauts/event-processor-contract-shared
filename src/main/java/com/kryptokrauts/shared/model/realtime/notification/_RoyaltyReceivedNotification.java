package com.kryptokrauts.shared.model.realtime.notification;

import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._PriceInfo;
import com.kryptokrauts.shared.model.realtime._Notification;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
public class _RoyaltyReceivedNotification extends _Notification {

  private _PriceInfo royaltyAmount;

  private _Asset asset;

  private Boolean bundle;

  private String marketType;
}

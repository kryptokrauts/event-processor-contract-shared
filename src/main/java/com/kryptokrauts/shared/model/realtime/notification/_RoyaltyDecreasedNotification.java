package com.kryptokrauts.shared.model.realtime.notification;

import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.realtime._Notification;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
public class _RoyaltyDecreasedNotification extends _Notification {

  private Double oldValue;

  private Double newValue;

  private _Account creator;
}

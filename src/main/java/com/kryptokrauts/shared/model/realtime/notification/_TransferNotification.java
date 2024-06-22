package com.kryptokrauts.shared.model.realtime.notification;

import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.realtime._Notification;

import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
@AllArgsConstructor
@NoArgsConstructor
public class _TransferNotification extends _Notification {

  private Long transferId;

  private _Asset asset;

  private _Account from;

  private Boolean bundle;
}

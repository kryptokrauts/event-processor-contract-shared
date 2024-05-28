package com.kryptokrauts.shared.model.realtime;

import com.kryptokrauts.shared.contract.types.NotificationType;
import com.kryptokrauts.shared.model._BaseModel;
import com.kryptokrauts.shared.model.common._Collection;
import io.quarkus.runtime.annotations.RegisterForReflection;
import java.util.Date;
import lombok.Getter;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@RegisterForReflection
public class _Notification extends _BaseModel {

  private Long notificationId;

  private Date receivedDate;

  private boolean acknowlegded;

  private Date acknowlegdedDate;

  private NotificationType type;

  private _Collection collection;
}

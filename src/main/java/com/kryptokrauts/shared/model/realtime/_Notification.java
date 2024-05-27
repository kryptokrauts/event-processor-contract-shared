package com.kryptokrauts.shared.model.realtime;

import com.kryptokrauts.shared.contract.types.NotificationType;
import com.kryptokrauts.shared.model._BaseModel;
import com.kryptokrauts.shared.model.common._Collection;
import io.quarkus.runtime.annotations.RegisterForReflection;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import lombok.Getter;
import lombok.experimental.SuperBuilder;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Schema(description = "user notification")
@Getter
@SuperBuilder
@RegisterForReflection
public class _Notification extends _BaseModel {

  private Long notificationId;

  private ChronoUnit receivedTimeUnit;

  private Integer receivedTimeValue;

  private Date receivedDate;

  @Schema(description = "user has actively acknowlegded the event")
  private boolean acknowlegded;

  @Schema(description = "date when the account acknowledged the notification")
  private Date acknowlegdedDate;

  private NotificationType type;

  private _Collection collection;
}

package com.kryptokrauts.shared.contract.handlers;

import com.kryptokrauts.shared.contract.types.NodeSyncStatusEvent;
import com.kryptokrauts.shared.contract.types.RawEvent;
import com.kryptokrauts.shared.contract.types.ResetEvent;
import contracts.event_log;
import contracts.node_sync_status_event;
import contracts.reset;
import io.quarkus.runtime.Quarkus;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;

@ApplicationScoped
public class DefaultHandler extends BaseHandler {

  @Inject
  @Channel("eventlog")
  Emitter<event_log> eventLogEmitter;

  @Inject
  @Channel("structured")
  Emitter<reset> resetEmitter;

  @Inject
  @Channel("structured")
  Emitter<node_sync_status_event> nodeSyncStatusEmitter;

  /**
   * persist event in event_log table
   *
   * @param event
   * @throws Exception
   */
  public void handleEvent(RawEvent event, String context) throws Exception {
    BaseHandler.logger.debugf(
        "Persisting incoming '%s' event at blocknum %d to event log",
        event.getType(), event.getBlocknum());

    event_log transformed = new event_log();

    transformed.setBlockTimestamp(event.getTimestamp());
    transformed.setBlocknum(event.getBlocknum());
    transformed.setTransactionId(event.getTransaction_id());
    transformed.setType(event.getType());
    transformed.setData(this.objectMapper.writeValueAsString(event.getData()));
    transformed.setGlobalSequence(event.getGlobal_sequence());

    this.emitTransformedMessage(transformed, this.eventLogEmitter, context);
  }

  /**
   * persist reset event and trigger database cleanup
   *
   * @param event
   */
  public void handleResetEvent(ResetEvent event, String context) {
    try {
      BaseHandler.logger.warnf(
          "Handling incoming reset event of type '%s' occurred at blocknum %d",
          event.getReset_type(), event.getReset_blocknum());

      reset reset = new reset();
      reset.setContext(context);
      reset.setBlocknum(event.getReset_blocknum());
      reset.setTimestamp(event.getTimestamp());
      reset.setDetails(event.getDetails());
      reset.setResetType(event.getReset_type());
      reset.setCleanDatabase(event.getClean_database() != null ? event.getClean_database() : false);
      reset.setCleanAfterBlocknum(event.getRestart_at_block());

      if (reset.getCleanDatabase()) {
        BaseHandler.logger.warnf(
            "Reset event clean database flag is set, cleaning database after blocknum %s",
            reset.getCleanAfterBlocknum());
      }

      this.emitTransformedMessage(reset, this.resetEmitter);
    } finally {
      BaseHandler.logger.warnf(
          "Stopping contract-processor because reset event was received at blocknum %s",
          event.getReset_blocknum());
      Quarkus.asyncExit(-1);
    }
  }

  /**
   * persist node sync status event
   *
   * @param event
   */
  public void handleNodeSyncStatus(NodeSyncStatusEvent event, String context) {
    BaseHandler.logger.debugf("Handling incoming node sync status event");

    node_sync_status_event sync_event = new node_sync_status_event();
    sync_event.setTimestamp(event.getTimestamp());
    sync_event.setProcessor(context);
    sync_event.setHeadBlock(event.getHead_block());
    sync_event.setCurrentBlock(event.getCurrent_block());
    sync_event.setDiff(event.getDiff());
    sync_event.setInSync(event.getIn_sync());
    sync_event.setCurrentSyncDate(event.getCurrent_sync_date());

    this.emitTransformedMessage(sync_event, this.nodeSyncStatusEmitter);
  }
}

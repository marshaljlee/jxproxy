import type { LogRecordExporter, ReadableLogRecord } from '@opentelemetry/sdk-logs'
import { ExportResultCode } from '@opentelemetry/core'

/**
 * First-party event logging exporter — stubbed by jxproxy.
 *
 * The original upstream implementation sends telemetry events to
 * api.anthropic.com/api/event_logging/batch. This stub eliminates
 * all of that code from the compiled binary.
 */
export class FirstPartyEventLoggingExporter implements LogRecordExporter {
  async export(
    _logs: ReadableLogRecord[],
    resultCallback: (result: { code: ExportResultCode }) => void,
  ): Promise<void> {
    resultCallback({ code: ExportResultCode.SUCCESS })
  }

  async shutdown(): Promise<void> {
    // no-op
  }

  async forceFlush(): Promise<void> {
    // no-op
  }
}

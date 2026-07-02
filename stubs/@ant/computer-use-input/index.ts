/**
 * Stub for @ant/computer-use-input
 *
 * Anthropic-internal package for computer use input handling (keyboard/mouse).
 * Loaded lazily via require() only when the Computer Use feature gate fires.
 * The require() is inside a try/catch guard in the actual source, so this
 * module is never actually accessed in the jxproxy fork.
 */

export type ComputerUseInput = {
  isSupported: boolean;
  [key: string]: any;
};

export type ComputerUseInputAPI = any;

export const isSupported = false;

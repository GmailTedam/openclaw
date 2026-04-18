import { beforeEach, describe, expect, it, vi } from "vitest";
import type { OpenClawConfig } from "../config/config.js";
import { buildTestCtx } from "./reply/test-ctx.js";

type DispatchReplyFromConfigFn =
  typeof import("./reply/dispatch-from-config.js").dispatchReplyFromConfig;
type FinalizeInboundContextFn = typeof import("./reply/inbound-context.js").finalizeInboundContext;

const hoisted = vi.hoisted(() => ({
  dispatchReplyFromConfigMock: vi.fn(),
  finalizeInboundContextMock: vi.fn((...args: unknown[]) => args[0]),
}));

vi.mock("./reply/dispatch-from-config.js", () => ({
  dispatchReplyFromConfig: (...args: Parameters<DispatchReplyFromConfigFn>) =>
    hoisted.dispatchReplyFromConfigMock(...args),
}));

vi.mock("./reply/inbound-context.js", () => ({
  finalizeInboundContext: (...args: Parameters<FinalizeInboundContextFn>) =>
    hoisted.finalizeInboundContextMock(...args),
}));

const { dispatchInboundMessageWithBufferedDispatcher } = await import("./dispatch.js");

type InternalReplyOptions = {
  onReplyStart?: () => Promise<void>;
};

describe("dispatch inbound typing on accept", () => {
  beforeEach(() => {
    hoisted.dispatchReplyFromConfigMock.mockReset();
    hoisted.finalizeInboundContextMock.mockClear();
  });

  it("starts typing before dispatch work begins and does not restart after a silent completion", async () => {
    const sendComposing = vi.fn(async () => undefined);
    let capturedReplyOptions: InternalReplyOptions | undefined;

    hoisted.dispatchReplyFromConfigMock.mockImplementationOnce(async (params: unknown) => {
      const replyParams = params as { replyOptions?: InternalReplyOptions };
      expect(sendComposing).toHaveBeenCalledTimes(1);
      capturedReplyOptions = replyParams.replyOptions;
      return undefined;
    });

    await dispatchInboundMessageWithBufferedDispatcher({
      ctx: buildTestCtx({
        ChatType: "direct",
        OriginatingChannel: "whatsapp",
        Provider: "whatsapp",
        Surface: "whatsapp",
      }),
      cfg: {} as OpenClawConfig,
      dispatcherOptions: {
        deliver: async () => undefined,
        onReplyStart: sendComposing,
        startTypingOnAccept: true,
      } as never,
    });

    expect(capturedReplyOptions?.onReplyStart).toBeTypeOf("function");

    await capturedReplyOptions?.onReplyStart?.();

    expect(sendComposing).toHaveBeenCalledTimes(1);
  });

  it("keeps the old deferred behavior when typing-on-accept is not enabled", async () => {
    const sendComposing = vi.fn(async () => undefined);

    hoisted.dispatchReplyFromConfigMock.mockImplementationOnce(async (params: unknown) => {
      const replyParams = params as { replyOptions?: InternalReplyOptions };
      expect(sendComposing).not.toHaveBeenCalled();
      await replyParams.replyOptions?.onReplyStart?.();
      expect(sendComposing).toHaveBeenCalledTimes(1);
      return undefined;
    });

    await dispatchInboundMessageWithBufferedDispatcher({
      ctx: buildTestCtx({
        ChatType: "direct",
        OriginatingChannel: "whatsapp",
        Provider: "whatsapp",
        Surface: "whatsapp",
      }),
      cfg: {} as OpenClawConfig,
      dispatcherOptions: {
        deliver: async () => undefined,
        onReplyStart: sendComposing,
      },
    });
  });
});

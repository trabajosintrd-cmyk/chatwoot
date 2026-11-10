import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import BaseActionCableConnector from '../BaseActionCableConnector';

const actionCableState = vi.hoisted(() => {
  const subscription = {
    updatePresence: vi.fn(),
  };
  const callbacks = { current: null };
  const consumer = {
    subscriptions: {
      create: vi.fn((_params, handlers) => {
        callbacks.current = handlers;
        return subscription;
      }),
    },
    connection: {
      isOpen: vi.fn(() => true),
    },
    disconnect: vi.fn(),
  };

  return {
    callbacks,
    consumer,
    createConsumer: vi.fn(() => consumer),
    subscription,
  };
});

vi.mock('@rails/actioncable', () => ({
  createConsumer: actionCableState.createConsumer,
}));

describe('BaseActionCableConnector lifecycle', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    actionCableState.callbacks.current = null;
    actionCableState.createConsumer.mockClear();
    actionCableState.consumer.disconnect.mockClear();
    actionCableState.consumer.connection.isOpen.mockReturnValue(true);
    actionCableState.consumer.subscriptions.create.mockClear();
    actionCableState.subscription.updatePresence.mockClear();
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  const createConnector = (presenceInterval = 20) =>
    new BaseActionCableConnector(
      {
        $store: {
          getters: {
            getCurrentAccountId: 12,
            getCurrentUserID: 34,
          },
        },
      },
      'test-pubsub-token',
      'wss://chatwoot.example.com',
      presenceInterval
    );

  it('uses the configured websocket host and sends presence while connected', () => {
    const connector = createConnector();

    expect(actionCableState.createConsumer).toHaveBeenCalledWith(
      'wss://chatwoot.example.com/cable'
    );

    vi.advanceTimersByTime(20);

    expect(
      actionCableState.subscription.updatePresence
    ).toHaveBeenCalledOnce();

    connector.disconnect();
  });

  it('clears presence and reconnect timers when manually disconnected', () => {
    const connector = createConnector();
    actionCableState.callbacks.current.disconnected();

    expect(vi.getTimerCount()).toBe(2);

    connector.disconnect();

    expect(vi.getTimerCount()).toBe(0);
    expect(actionCableState.consumer.disconnect).toHaveBeenCalledOnce();

    vi.advanceTimersByTime(60_000);

    expect(
      actionCableState.subscription.updatePresence
    ).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
  });
});

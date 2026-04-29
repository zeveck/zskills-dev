import { describe, it, expect, beforeEach } from 'vitest';
import beta from './beta.js';

describe('beta', () => {
  let state;
  beforeEach(() => {
    state = { count: 0 };
  });

  it('increments via fixture', () => {
    state.count = beta(state.count);
    expect(state.count).toBe(1);
  });

  it('handles repeated invocation', () => {
    state.count = beta(beta(state.count));
    expect(state.count).toBe(2);
  });

  it('rejects negative input', () => {
    expect(() => beta(-1)).toThrow();
  });
});

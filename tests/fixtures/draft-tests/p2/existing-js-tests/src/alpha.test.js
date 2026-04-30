import { describe, it, expect } from 'vitest';
import alpha from './alpha.js';

describe('alpha', () => {
  it('handles a basic case', () => {
    expect(alpha(1)).toBe(1);
  });
  it('handles a second case', () => {
    expect(alpha(2)).toBe(2);
  });
});

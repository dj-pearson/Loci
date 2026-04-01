/**
 * Input validation and sanitization for edge function API boundaries.
 */

const MAX_LENGTHS = {
  householdId: 36,  // UUID format
  code: 10,         // Invite codes are 6 chars, allow slight buffer
  displayName: 50,
  householdName: 50,
  transcription: 5000,
} as const;

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const INVITE_CODE_REGEX = /^[A-Z0-9]{4,8}$/;

/** Strip HTML tags, control characters, and zero-width characters from text. */
export function sanitizeText(text: string, maxLength: number): string {
  let result = text;

  // Strip HTML/script tags
  result = result.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
  result = result.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
  result = result.replace(/<[^>]+>/g, '');

  // Remove null bytes
  result = result.replace(/\0/g, '');

  // Remove control characters (keep newline/tab)
  result = result.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');

  // Remove zero-width characters
  result = result.replace(/[\u200B\u200C\u200D\uFEFF\u00AD\u2060\u180E]/g, '');

  // Trim and truncate
  result = result.trim();
  if (result.length > maxLength) {
    result = result.slice(0, maxLength);
  }

  return result;
}

/** Validate that a string is a valid UUID v4 format. */
export function isValidUUID(value: unknown): value is string {
  return typeof value === 'string' && UUID_REGEX.test(value);
}

/** Validate an invite code format. */
export function isValidInviteCode(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const upper = value.toUpperCase().trim();
  return INVITE_CODE_REGEX.test(upper) && upper.length <= MAX_LENGTHS.code;
}

/** Validate that a value is a non-empty string within max length. */
export function isValidString(value: unknown, maxLength: number): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= maxLength;
}

export { MAX_LENGTHS };

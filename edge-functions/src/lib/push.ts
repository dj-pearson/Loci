import { sendApnsPush, type SendApnsOptions } from './apns.js';
import { sendFcmPush, type SendFcmOptions } from './fcm.js';
import { log } from './logger.js';

/**
 * Platform-agnostic push dispatch (US-197).
 *
 * `push-digest` previously knew only about `apns_token`. Now every send goes
 * through here, which picks the transport per row — so a new caller cannot
 * accidentally reach iOS users only, which is exactly how Android ended up with
 * no notifications.
 */

export interface PushRecipient {
  /** `public.users.id`, used to clear a dead token. */
  userId: string;
  apnsToken?: string | null;
  fcmToken?: string | null;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Deep-link target; delivered as `locus_id` on both platforms. */
  locusId?: string;
  /** Coalesces repeat sends of the same logical notification. */
  collapseId?: string;
  threadId?: string;
}

export interface PushDeliveryResult {
  /** Platforms that accepted the message. */
  delivered: Array<'ios' | 'android'>;
  /** Platforms whose token is permanently dead and must be cleared. */
  invalid: Array<'ios' | 'android'>;
  /** Platforms that failed transiently, or were not configured. */
  failed: Array<'ios' | 'android'>;
  /** True when the recipient had no token on any platform. */
  noTokens: boolean;
}

export interface DispatchOptions {
  apns?: SendApnsOptions;
  fcm?: SendFcmOptions;
}

export async function dispatchPush(
  recipient: PushRecipient,
  message: PushMessage,
  options: DispatchOptions = {}
): Promise<PushDeliveryResult> {
  const result: PushDeliveryResult = {
    delivered: [],
    invalid: [],
    failed: [],
    noTokens: !recipient.apnsToken && !recipient.fcmToken,
  };

  if (result.noTokens) return result;

  // A user with both an iPhone and an Android device should get the notification
  // on both, so these run together rather than first-match-wins.
  const sends: Array<Promise<void>> = [];

  if (recipient.apnsToken) {
    sends.push(
      sendApnsPush(
        recipient.apnsToken,
        {
          title: message.title,
          body: message.body,
          threadId: message.threadId,
          collapseId: message.collapseId,
          data: message.locusId ? { locusId: message.locusId } : undefined,
        },
        options.apns ?? {}
      ).then((outcome) => {
        if (outcome.ok) result.delivered.push('ios');
        else if (outcome.invalidToken) result.invalid.push('ios');
        else result.failed.push('ios');

        if (!outcome.ok && !outcome.skipped) {
          log.warn('apns delivery failed', {
            userId: recipient.userId,
            status: outcome.status,
            reason: outcome.reason,
          });
        }
      })
    );
  }

  if (recipient.fcmToken) {
    sends.push(
      sendFcmPush(
        recipient.fcmToken,
        {
          title: message.title,
          body: message.body,
          collapseKey: message.collapseId,
          // Android reads locus_id from the data payload; the key is snake_case to
          // match LociateMessagingService.
          data: message.locusId ? { locus_id: message.locusId } : undefined,
        },
        options.fcm ?? {}
      ).then((outcome) => {
        if (outcome.ok) result.delivered.push('android');
        else if (outcome.invalidToken) result.invalid.push('android');
        else result.failed.push('android');

        if (!outcome.ok && !outcome.skipped) {
          log.warn('fcm delivery failed', {
            userId: recipient.userId,
            status: outcome.status,
            reason: outcome.reason,
          });
        }
      })
    );
  }

  await Promise.all(sends);
  return result;
}

/** Column name to null out for a platform whose token is dead. */
export function tokenColumnFor(platform: 'ios' | 'android'): 'apns_token' | 'fcm_token' {
  return platform === 'ios' ? 'apns_token' : 'fcm_token';
}

-- Migration 009: Login attempt tracking for brute force protection (US-146)
-- Tracks failed authentication attempts per email and IP for server-side lockout.

-- Login attempts table
CREATE TABLE IF NOT EXISTS login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    ip_address INET NOT NULL,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    success BOOLEAN NOT NULL DEFAULT false,
    user_agent TEXT,
    failure_reason TEXT
);

-- Indexes for efficient querying
CREATE INDEX idx_login_attempts_email_time ON login_attempts (email, attempted_at DESC);
CREATE INDEX idx_login_attempts_ip_time ON login_attempts (ip_address, attempted_at DESC);
CREATE INDEX idx_login_attempts_cleanup ON login_attempts (attempted_at);

-- RLS: Only service role can access login_attempts (no user access)
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

-- No user-facing policies — only service role (bypasses RLS) can read/write.
-- This prevents users from seeing or manipulating attempt records.

-- Function: Check if an email is currently locked out
-- Returns lockout status and seconds remaining
CREATE OR REPLACE FUNCTION check_auth_lockout(
    p_email TEXT,
    p_ip INET DEFAULT NULL,
    p_max_email_attempts INT DEFAULT 10,
    p_max_ip_attempts INT DEFAULT 20,
    p_window_minutes INT DEFAULT 15,
    p_lockout_minutes INT DEFAULT 60
)
RETURNS TABLE (
    is_locked_out BOOLEAN,
    lockout_seconds_remaining INT,
    reason TEXT,
    recent_failures INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_email_failures INT;
    v_ip_failures INT;
    v_last_failure TIMESTAMPTZ;
    v_lockout_end TIMESTAMPTZ;
BEGIN
    v_window_start := now() - (p_window_minutes || ' minutes')::INTERVAL;

    -- Count failed attempts for this email in the window
    SELECT COUNT(*), MAX(attempted_at)
    INTO v_email_failures, v_last_failure
    FROM login_attempts
    WHERE email = lower(p_email)
      AND attempted_at > v_window_start
      AND success = false;

    -- Check email-based lockout
    IF v_email_failures >= p_max_email_attempts THEN
        v_lockout_end := v_last_failure + (p_lockout_minutes || ' minutes')::INTERVAL;
        IF v_lockout_end > now() THEN
            RETURN QUERY SELECT
                true,
                EXTRACT(EPOCH FROM (v_lockout_end - now()))::INT,
                'Too many failed attempts for this email'::TEXT,
                v_email_failures;
            RETURN;
        END IF;
    END IF;

    -- Check IP-based lockout (if IP provided)
    IF p_ip IS NOT NULL THEN
        SELECT COUNT(*)
        INTO v_ip_failures
        FROM login_attempts
        WHERE ip_address = p_ip
          AND attempted_at > v_window_start
          AND success = false;

        IF v_ip_failures >= p_max_ip_attempts THEN
            v_lockout_end := now() + (p_lockout_minutes || ' minutes')::INTERVAL;
            RETURN QUERY SELECT
                true,
                EXTRACT(EPOCH FROM (v_lockout_end - now()))::INT,
                'Too many failed attempts from this IP'::TEXT,
                v_ip_failures;
            RETURN;
        END IF;
    END IF;

    -- Not locked out
    RETURN QUERY SELECT false, 0, NULL::TEXT, v_email_failures;
END;
$$;

-- Function: Record a login attempt
CREATE OR REPLACE FUNCTION record_login_attempt(
    p_email TEXT,
    p_ip INET,
    p_success BOOLEAN,
    p_user_agent TEXT DEFAULT NULL,
    p_failure_reason TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO login_attempts (email, ip_address, success, user_agent, failure_reason)
    VALUES (lower(p_email), p_ip, p_success, p_user_agent, p_failure_reason);

    -- If successful, optionally clear old failures for this email
    -- (keeps history but resets lockout window)
    IF p_success THEN
        -- Mark recent failures as "resolved" by deleting them
        -- Keep successful attempts for audit trail
        DELETE FROM login_attempts
        WHERE email = lower(p_email)
          AND success = false
          AND attempted_at > now() - INTERVAL '1 hour';
    END IF;
END;
$$;

-- Cleanup: Delete attempt records older than 30 days
-- Should be run via cron (e.g., daily at 3 AM)
CREATE OR REPLACE FUNCTION cleanup_login_attempts(
    p_retention_days INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted INT;
BEGIN
    DELETE FROM login_attempts
    WHERE attempted_at < now() - (p_retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

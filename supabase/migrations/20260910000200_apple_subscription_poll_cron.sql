-- Schedules a daily call to `apple-subscription-poll`, which is how Apple
-- subscription renewals get recorded — Apple never calls us back the way
-- Paystack's webhook does, so this is the only mechanism that notices a
-- renewal happened.
--
-- The Authorization header just needs to be *some* valid Supabase-issued
-- JWT to pass the function gateway's default check (the anon key qualifies,
-- and is already public/embedded in the app itself) — the actual "this is
-- really the cron job" check happens inside the function itself, via the
-- x-cron-secret header matched against the CRON_POLL_SECRET Edge Function
-- secret.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'apple-subscription-poll-daily',
  '0 3 * * *', -- 03:00 UTC daily
  $$
  select net.http_post(
    url := 'https://bnrrbsvzclcmoifztkic.supabase.co/functions/v1/apple-subscription-poll',
    headers := jsonb_build_object(
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJucnJic3Z6Y2xjbW9pZnp0a2ljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MTc2OTMsImV4cCI6MjA5NTI5MzY5M30.nI1rCVvznmgrM1nFX6U71d9gHp_liMIm5LzFoewnN9o',
      'x-cron-secret', 'a4f87c0572893bccb5b2114787d4b491d0055636d843ce8a162de31e34801b36',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

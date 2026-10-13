-- Research quotations. A newly posted research request is held back
-- (hidden from the board, unclaimable) while RootSphere reviews it and sends
-- the requester an itemised quotation. The requester accepts (then pays via
-- Paystack) or declines; only once payment is confirmed is the request
-- released to researchers. Run AFTER 20261006000000_researcher_undertakings.sql.
--
-- opportunities.quote_state:
--   null            legacy rows / requests posted by admins — never held
--   awaiting_quote  posted, waiting for RootSphere to send a quotation
--   quoted          quotation sent, waiting for the requester
--   accepted        requester accepted, payment not yet confirmed
--   declined        requester declined (admin may send a revised quote)
--   paid            payment confirmed — released to the board

alter table public.opportunities
  add column if not exists quote_state text
    check (quote_state in ('awaiting_quote', 'quoted', 'accepted', 'declined', 'paid'));

create table if not exists public.research_quotations (
  id                uuid primary key default gen_random_uuid(),
  opportunity_id    text not null references public.opportunities (id) on delete cascade,
  line_items        jsonb not null default '[]'::jsonb, -- [{description, amount_cents}]
  total_cents       bigint not null check (total_cents > 0),
  currency          text not null default 'ngn',
  timeframe         text not null default '',
  notes             text not null default '',
  valid_until       date,
  status            text not null default 'sent'
                      check (status in ('sent', 'accepted', 'declined', 'paid', 'superseded')),
  decline_reason    text,
  payment_reference text unique,
  created_by        uuid references auth.users (id),
  created_at        timestamptz not null default now(),
  responded_at      timestamptz,
  paid_at           timestamptz
);

create index if not exists research_quotations_opportunity_idx
  on public.research_quotations (opportunity_id, created_at desc);

alter table public.research_quotations enable row level security;

-- Read: the opportunity's requester and admins. All writes go through the
-- SECURITY DEFINER functions below — no insert/update/delete policies.
drop policy if exists "research_quotations_select" on public.research_quotations;
create policy "research_quotations_select" on public.research_quotations
  for select to authenticated
  using (
    public.is_platform_admin()
    or exists (
      select 1 from public.opportunities o
      where o.id = research_quotations.opportunity_id
        and o.requester_id = auth.uid()
    )
  );

-- ── Hold new requests ────────────────────────────────────────────────────────

create or replace function public.hold_new_request_for_quote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_platform_admin() then
    new.quote_state := null; -- the company's own postings skip quoting
  else
    new.quote_state := 'awaiting_quote';
  end if;
  return new;
end;
$$;

drop trigger if exists opportunities_hold_for_quote on public.opportunities;
create trigger opportunities_hold_for_quote
  before insert on public.opportunities
  for each row execute function public.hold_new_request_for_quote();

-- quote_state may only be changed by the quotation functions below (which
-- set rootsphere.quote_ctx for the duration of their own statement) — stops
-- a requester from simply PATCHing their own row to 'paid'.
create or replace function public.guard_quote_state()
returns trigger
language plpgsql
as $$
begin
  if new.quote_state is distinct from old.quote_state
     and coalesce(current_setting('rootsphere.quote_ctx', true), '') <> 'on' then
    raise exception 'quote_state_read_only' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists opportunities_guard_quote_state on public.opportunities;
create trigger opportunities_guard_quote_state
  before update on public.opportunities
  for each row execute function public.guard_quote_state();

-- Visibility: held requests are only visible to their requester and admins.
drop policy if exists "opportunities_select" on public.opportunities;
create policy "opportunities_select" on public.opportunities
  for select
  to authenticated
  using (
    (for_company = false and (quote_state is null or quote_state = 'paid'))
    or requester_id = auth.uid()
    or claimer_id = auth.uid()
    or public.is_platform_admin()
  );

-- Claiming: nobody (admins included) can claim a request until it's paid.
create or replace function public.check_claim_qualification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'open' and new.status = 'claimed' and new.claimer_id is not null then
    if new.quote_state is not null and new.quote_state <> 'paid' then
      raise exception 'awaiting_quotation' using errcode = 'insufficient_privilege';
    end if;
    if not exists (
      select 1 from public.researcher_undertakings ru
      where ru.user_id = new.claimer_id
        and ru.version = '2026-10'
    ) then
      raise exception 'undertaking_required'
        using errcode = 'insufficient_privilege';
    end if;
    if public.is_platform_admin() then
      return new;
    end if;
    if new.for_company then
      raise exception 'company_request_admin_only'
        using errcode = 'insufficient_privilege';
    end if;
    if not exists (
      select 1 from public.role_verifications rv
      where rv.user_id = new.claimer_id
        and rv.role = new.required_role
        and rv.status = 'approved'
    ) then
      raise exception 'not_qualified_for_role: %', new.required_role
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

-- ── Notifications helper ─────────────────────────────────────────────────────

create or replace function public.notify_quote_admins(
  p_type text, p_title text, p_body text, p_opportunity_id text, p_tree_id text
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
  select a.user_id, p_type, p_title, p_body, p_tree_id, p_opportunity_id
  from public.platform_admins a;
$$;

create or replace function public.notify_new_request_awaiting_quote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.quote_state = 'awaiting_quote' then
    perform public.notify_quote_admins(
      'quotation_requested',
      'New research request to quote',
      coalesce(new.requester_name, 'Someone') || ' submitted "' || new.title
        || '". Review it and send a quotation.',
      new.id, new.tree_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists opportunities_notify_awaiting_quote on public.opportunities;
create trigger opportunities_notify_awaiting_quote
  after insert on public.opportunities
  for each row execute function public.notify_new_request_awaiting_quote();

-- ── Admin: send a quotation ──────────────────────────────────────────────────

create or replace function public.send_research_quotation(
  p_opportunity_id text,
  p_line_items     jsonb,
  p_timeframe      text,
  p_notes          text,
  p_valid_until    date,
  p_currency       text default 'ngn'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opp   public.opportunities;
  v_total bigint;
  v_id    uuid;
  v_item  jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'admin_only' using errcode = 'insufficient_privilege';
  end if;
  select * into v_opp from public.opportunities where id = p_opportunity_id for update;
  if not found then
    raise exception 'opportunity_not_found';
  end if;
  if v_opp.quote_state is null or v_opp.quote_state in ('accepted', 'paid') then
    raise exception 'quotation_not_allowed: %', coalesce(v_opp.quote_state, 'not_held');
  end if;
  if jsonb_typeof(p_line_items) <> 'array' or jsonb_array_length(p_line_items) = 0 then
    raise exception 'line_items_required';
  end if;
  for v_item in select * from jsonb_array_elements(p_line_items) loop
    if coalesce(trim(v_item->>'description'), '') = ''
       or (v_item->>'amount_cents')::bigint <= 0 then
      raise exception 'invalid_line_item';
    end if;
  end loop;
  select sum((e->>'amount_cents')::bigint) into v_total
  from jsonb_array_elements(p_line_items) e;

  update public.research_quotations
     set status = 'superseded'
   where opportunity_id = p_opportunity_id and status in ('sent', 'declined');

  insert into public.research_quotations
    (opportunity_id, line_items, total_cents, currency, timeframe, notes, valid_until, created_by)
  values
    (p_opportunity_id, p_line_items, v_total, lower(coalesce(p_currency, 'ngn')),
     coalesce(p_timeframe, ''), coalesce(p_notes, ''), p_valid_until, auth.uid())
  returning id into v_id;

  perform set_config('rootsphere.quote_ctx', 'on', true);
  update public.opportunities set quote_state = 'quoted' where id = p_opportunity_id;
  perform set_config('rootsphere.quote_ctx', 'off', true);

  insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
  values (
    v_opp.requester_id, 'quotation_sent', 'Your quotation is ready',
    'RootSphere sent a quotation for "' || v_opp.title || '". Review it to accept or decline.',
    v_opp.tree_id, v_opp.id
  );
  return v_id;
end;
$$;

grant execute on function public.send_research_quotation(text, jsonb, text, text, date, text) to authenticated;

-- ── Requester: accept or decline ─────────────────────────────────────────────

create or replace function public.respond_research_quotation(
  p_quotation_id uuid,
  p_accept       boolean,
  p_reason       text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q   public.research_quotations;
  v_opp public.opportunities;
begin
  select * into v_q from public.research_quotations where id = p_quotation_id for update;
  if not found then
    raise exception 'quotation_not_found';
  end if;
  select * into v_opp from public.opportunities where id = v_q.opportunity_id;
  if v_opp.requester_id is distinct from auth.uid() then
    raise exception 'only_requester_can_respond' using errcode = 'insufficient_privilege';
  end if;
  if v_q.status <> 'sent' then
    raise exception 'quotation_not_open';
  end if;
  if p_accept and v_q.valid_until is not null and v_q.valid_until < current_date then
    raise exception 'quotation_expired';
  end if;

  update public.research_quotations
     set status = case when p_accept then 'accepted' else 'declined' end,
         decline_reason = case when p_accept then null else nullif(trim(p_reason), '') end,
         responded_at = now()
   where id = p_quotation_id;

  perform set_config('rootsphere.quote_ctx', 'on', true);
  update public.opportunities
     set quote_state = case when p_accept then 'accepted' else 'declined' end
   where id = v_opp.id;
  perform set_config('rootsphere.quote_ctx', 'off', true);

  perform public.notify_quote_admins(
    case when p_accept then 'quotation_accepted' else 'quotation_declined' end,
    case when p_accept then 'Quotation accepted' else 'Quotation declined' end,
    coalesce(v_opp.requester_name, 'The requester')
      || case when p_accept then ' accepted' else ' declined' end
      || ' the quotation for "' || v_opp.title || '"'
      || case when p_accept then ' and is proceeding to payment.'
              else coalesce(': ' || nullif(trim(p_reason), ''), '.') end,
    v_opp.id, v_opp.tree_id
  );
end;
$$;

grant execute on function public.respond_research_quotation(uuid, boolean, text) to authenticated;

-- ── Payment (called by edge functions with the service role) ────────────────

-- Records the Paystack reference minted for an accepted quotation.
create or replace function public.attach_quotation_payment_reference(
  p_quotation_id uuid, p_reference text
) returns void
language sql
security definer
set search_path = public
as $$
  update public.research_quotations
     set payment_reference = p_reference
   where id = p_quotation_id and status = 'accepted';
$$;

-- Marks a quotation paid and releases its request to the board. Idempotent
-- (Paystack may deliver the same webhook more than once).
create or replace function public.mark_quotation_paid(p_reference text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q   public.research_quotations;
  v_opp public.opportunities;
begin
  select * into v_q from public.research_quotations
   where payment_reference = p_reference for update;
  if not found or v_q.status = 'paid' then
    return;
  end if;
  update public.research_quotations
     set status = 'paid', paid_at = now()
   where id = v_q.id;

  perform set_config('rootsphere.quote_ctx', 'on', true);
  update public.opportunities set quote_state = 'paid'
   where id = v_q.opportunity_id
  returning * into v_opp;
  perform set_config('rootsphere.quote_ctx', 'off', true);

  insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
  values (
    v_opp.requester_id, 'quotation_paid', 'Payment received',
    'Thank you — payment for "' || v_opp.title || '" is confirmed and your request '
      || 'is now with our researchers.',
    v_opp.tree_id, v_opp.id
  );
  perform public.notify_quote_admins(
    'quotation_paid', 'Quotation paid',
    coalesce(v_opp.requester_name, 'The requester') || ' paid for "' || v_opp.title
      || '". It is now released to researchers.',
    v_opp.id, v_opp.tree_id
  );
end;
$$;

revoke all on function public.attach_quotation_payment_reference(uuid, text) from public, anon, authenticated;
revoke all on function public.mark_quotation_paid(text) from public, anon, authenticated;
grant execute on function public.attach_quotation_payment_reference(uuid, text) to service_role;
grant execute on function public.mark_quotation_paid(text) to service_role;

-- Live updates so the requester/admin screens refresh as states change.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'research_quotations'
  ) then
    alter publication supabase_realtime add table public.research_quotations;
  end if;
end $$;
